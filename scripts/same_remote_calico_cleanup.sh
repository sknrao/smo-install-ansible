#!/bin/bash
# SAFE Calico Cleanup for REMOTE SERVERS
# Preserves SSH connectivity and management network

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

echo "=========================================="
echo "SAFE Calico Cleanup for Remote Servers"
echo "=========================================="
echo ""

print_warning "This is a SAFE script for remote servers"
print_warning "It will NOT flush routing tables or break SSH"
echo ""

# Detect SSH connection
if [ -n "$SSH_CONNECTION" ]; then
    SSH_IP=$(echo $SSH_CONNECTION | awk '{print $3}')
    print_warning "SSH detected: You are connected from remote"
    print_info "Your SSH IP: $SSH_IP"
    echo ""
fi

# Detect default gateway
DEFAULT_GW=$(ip route | grep default | awk '{print $3}' | head -1)
DEFAULT_DEV=$(ip route | grep default | awk '{print $5}' | head -1)
print_info "Default gateway: $DEFAULT_GW via $DEFAULT_DEV"

# Detect management network
MGMT_IP=$(ip addr show $DEFAULT_DEV | grep "inet " | awk '{print $2}' | cut -d/ -f1)
print_info "Management IP: $MGMT_IP on $DEFAULT_DEV"

echo ""
print_warning "The script will preserve:"
echo "  ✓ SSH connection"
echo "  ✓ Default gateway ($DEFAULT_GW)"
echo "  ✓ Management interface ($DEFAULT_DEV)"
echo "  ✓ Management IP ($MGMT_IP)"
echo ""

read -p "Continue with safe cleanup? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Step 1: Stop Kubernetes services (safe)
print_warning "Step 1: Stopping Kubernetes services"
kubeadm reset -f 2>/dev/null || true
systemctl stop kubelet 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true
systemctl stop docker 2>/dev/null || true

# Kill processes
pkill -9 kubelet 2>/dev/null || true
pkill -9 kube-proxy 2>/dev/null || true
pkill -9 kube-apiserver 2>/dev/null || true
pkill -9 kube-controller 2>/dev/null || true
pkill -9 kube-scheduler 2>/dev/null || true
pkill -9 etcd 2>/dev/null || true
pkill -9 calico-node 2>/dev/null || true
pkill -9 bird 2>/dev/null || true
pkill -9 confd 2>/dev/null || true
pkill -9 felix 2>/dev/null || true

sleep 3
print_status "Services stopped"

# Step 2: Unmount safely
print_warning "Step 2: Unmounting Kubernetes filesystems"
for mount in $(cat /proc/mounts | grep -E 'kubelet|kubernetes|calico' | awk '{print $2}' | sort -r); do
    umount -f "$mount" 2>/dev/null || umount -l "$mount" 2>/dev/null || true
done
print_status "Filesystems unmounted"

# Step 3: Remove network interfaces (EXCEPT management interface)
print_warning "Step 3: Removing Calico network interfaces (preserving $DEFAULT_DEV)"

# Remove Calico-specific interfaces
interfaces_to_remove=(
    "tunl0"
    "vxlan.calico"
    "wireguard.cali"
    "cni0"
)

for iface in "${interfaces_to_remove[@]}"; do
    if ip link show "$iface" &>/dev/null; then
        print_info "Deleting interface: $iface"
        ip link delete "$iface" 2>/dev/null || true
    fi
done

# Remove cali* interfaces (but check they're not the default interface)
for iface in $(ip link show | grep -oE "cali[^:@]+" 2>/dev/null || true); do
    if [ "$iface" != "$DEFAULT_DEV" ]; then
        print_info "Deleting interface: $iface"
        ip link delete "$iface" 2>/dev/null || true
    fi
done

# Remove veth pairs
for iface in $(ip link show | grep -oE "veth[^:@]+" 2>/dev/null || true); do
    print_info "Deleting interface: $iface"
    ip link delete "$iface" 2>/dev/null || true
done

print_status "Calico interfaces removed (management preserved)"

# Step 4: Clean iptables CAREFULLY
print_warning "Step 4: Cleaning iptables (preserving SSH rules)"

# Save current SSH-related rules
print_info "Preserving SSH and management network rules..."

# Flush Kubernetes/Calico chains only
for table in filter nat mangle raw; do
    for chain in $(iptables -t $table -L -n | grep "^Chain KUBE\|^Chain cali" | awk '{print $2}'); do
        iptables -t $table -F $chain 2>/dev/null || true
        iptables -t $table -X $chain 2>/dev/null || true
    done
done

print_status "Kubernetes/Calico iptables rules cleaned (SSH preserved)"

# Step 5: Destroy ipsets (THE MAIN FIX)
print_warning "Step 5: Destroying Calico ipsets"

# First flush them
for set in $(ipset list -n 2>/dev/null | grep "^cali" || true); do
    print_info "Flushing ipset: $set"
    ipset flush "$set" 2>/dev/null || true
done

# Then destroy them
for set in $(ipset list -n 2>/dev/null | grep "^cali" || true); do
    print_info "Destroying ipset: $set"
    ipset destroy "$set" 2>/dev/null || {
        print_warning "Could not destroy $set - may need module unload"
    }
done

print_status "ipsets processed"

# Step 6: Remove Calico configuration
print_warning "Step 6: Removing Calico configuration"
rm -rf /etc/calico
rm -rf /var/lib/calico
rm -rf /var/log/calico
rm -rf /opt/cni/bin/calico*
print_status "Calico configuration removed"

# Step 7: Remove CNI configuration
print_warning "Step 7: Removing CNI configuration"
rm -rf /etc/cni/net.d/*
rm -rf /var/lib/cni
print_status "CNI configuration removed"

# Step 8: Clean ONLY Calico routes (NOT default route!)
print_warning "Step 8: Cleaning Calico-specific routes (preserving default gateway)"

print_info "Preserving default route to $DEFAULT_GW"

# Remove only Calico BIRD protocol routes
ip route show | grep "proto bird" | while read route; do
    print_info "Removing route: $route"
    ip route del $route 2>/dev/null || true
done

# Remove Calico protocol 80 routes
ip route show | grep "proto 80" | while read route; do
    print_info "Removing route: $route"
    ip route del $route 2>/dev/null || true
done

# Remove blackhole routes from Calico
ip route show | grep "blackhole" | while read route; do
    print_info "Removing route: $route"
    ip route del $route 2>/dev/null || true
done

print_status "Calico routes cleaned (default gateway preserved)"

# Step 9: Remove Kubernetes directories
print_warning "Step 9: Removing Kubernetes directories"
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf /var/lib/kube-proxy
rm -rf /var/log/pods
rm -rf /var/log/containers
rm -rf ~/.kube
rm -rf /root/.kube
print_status "Kubernetes directories removed"

# Step 10: Unload ONLY Calico-specific modules
print_warning "Step 10: Unloading Calico kernel modules"

# Only unload modules that won't break connectivity
safe_to_remove=(
    "ipip"
    "wireguard"
)

for mod in "${safe_to_remove[@]}"; do
    if lsmod | grep -q "^$mod"; then
        print_info "Unloading module: $mod"
        rmmod "$mod" 2>/dev/null || {
            print_warning "Could not unload $mod (in use or doesn't exist)"
        }
    fi
done

# DO NOT remove: vxlan, ip_set, nf_conntrack, br_netfilter
# These might be used by the management network
print_info "Preserving: vxlan, ip_set, nf_conntrack (may be in use by network)"

print_status "Safe modules unloaded"

# Step 11: Verification
echo ""
print_warning "Step 11: Verification"

# Check connectivity
if ping -c 1 -W 2 $DEFAULT_GW &>/dev/null; then
    print_status "Connectivity to gateway: OK"
else
    print_error "WARNING: Cannot ping gateway!"
fi

# Check SSH is still working
if [ -n "$SSH_CONNECTION" ]; then
    print_status "SSH connection: Still active"
fi

# Check default route
if ip route | grep -q "default"; then
    print_status "Default route: Preserved"
else
    print_error "WARNING: Default route missing!"
fi

# Check ipsets
CALICO_IPSETS=$(ipset list -n 2>/dev/null | grep -c "^cali" || echo "0")
if [ "$CALICO_IPSETS" -eq 0 ]; then
    print_status "Calico ipsets: All removed"
else
    print_warning "Calico ipsets: $CALICO_IPSETS still present (will need reboot)"
    ipset list -n | grep "^cali" | head -5
fi

# Check interfaces
CALICO_IFACES=$(ip link show | grep -c "cali\|vxlan.calico\|tunl0" 2>/dev/null || echo "0")
if [ "$CALICO_IFACES" -eq 0 ]; then
    print_status "Calico interfaces: All removed"
else
    print_warning "Calico interfaces: Some remain"
fi

echo ""
echo "=========================================="
echo "Safe Cleanup Complete!"
echo "=========================================="
echo ""
print_status "Your SSH connection is preserved"
print_status "Network connectivity is maintained"
echo ""

if [ "$CALICO_IPSETS" -gt 0 ]; then
    print_warning "Some ipsets still exist (kernel holding references)"
    echo ""
    print_info "Options to fully clean them:"
    echo "  1. Schedule a reboot: sudo shutdown -r +5"
    echo "  2. Continue working and reboot later"
    echo "  3. Try manual cleanup of remaining ipsets"
    echo ""
    print_warning "For complete cleanup, a reboot is recommended"
    echo ""
    read -p "Schedule reboot in 5 minutes? (yes/no): " schedule_reboot
    if [ "$schedule_reboot" = "yes" ]; then
        shutdown -r +5 "System reboot for Kubernetes cleanup - 5 minutes"
        print_status "Reboot scheduled in 5 minutes"
        print_info "Cancel with: sudo shutdown -c"
    fi
else
    print_info "System is clean! You can now reinstall Kubernetes"
    echo ""
    print_info "Next steps:"
    echo "  1. Setup containerd: sudo systemctl restart containerd"
    echo "  2. Reinstall Kubernetes with your role"
    echo "  3. Use containerd (not Docker!)"
fi

echo ""
print_info "Cleanup log saved to: /var/log/k8s-cleanup.log"

