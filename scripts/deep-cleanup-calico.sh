#!/bin/bash
# Complete Calico and Kernel Network Cleanup
# Fixes: "Set cannot be destroyed: it is in use by a kernel component"

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

echo "=========================================="
echo "Deep Calico/Network Cleanup"
echo "=========================================="
echo ""

# Step 1: Stop everything
print_warning "Step 1: Stopping all Kubernetes services"
kubeadm reset -f 2>/dev/null || true
systemctl stop kubelet 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true
systemctl stop docker 2>/dev/null || true

# Kill all processes
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

# Step 2: Delete all Calico pods and resources (if cluster still exists)
print_warning "Step 2: Cleaning Calico resources"
if kubectl get nodes &>/dev/null 2>&1; then
    kubectl delete pod -n kube-system -l k8s-app=calico-node --force --grace-period=0 2>/dev/null || true
    kubectl delete pod -n kube-system -l k8s-app=calico-kube-controllers --force --grace-period=0 2>/dev/null || true
    kubectl delete pod -n calico-system --all --force --grace-period=0 2>/dev/null || true
    kubectl delete pod -n calico-apiserver --all --force --grace-period=0 2>/dev/null || true
    kubectl delete pod -n tigera-operator --all --force --grace-period=0 2>/dev/null || true
    sleep 2
fi
print_status "Calico resources deleted"

# Step 3: Unmount everything
print_warning "Step 3: Unmounting filesystems"
for mount in $(cat /proc/mounts | grep -E 'kubelet|kubernetes|calico' | awk '{print $2}' | sort -r); do
    umount -f "$mount" 2>/dev/null || umount -l "$mount" 2>/dev/null || true
done
print_status "Filesystems unmounted"

# Step 4: CRITICAL - Remove all network interfaces
print_warning "Step 4: Removing network interfaces"
interfaces=(
    "cali.*"
    "tunl0"
    "vxlan.calico"
    "wireguard.cali"
    "cni0"
    "flannel.*"
    "docker0"
    "veth.*"
)

for pattern in "${interfaces[@]}"; do
    for iface in $(ip link show | grep -oE "$pattern" 2>/dev/null || true); do
        print_warning "Deleting interface: $iface"
        ip link delete "$iface" 2>/dev/null || true
    done
done

# Delete specific Calico interfaces
ip link delete tunl0 2>/dev/null || true
ip link delete vxlan.calico 2>/dev/null || true
ip link delete wireguard.cali 2>/dev/null || true
ip link delete cni0 2>/dev/null || true

print_status "Network interfaces removed"

# Step 5: CRITICAL - Flush all iptables rules
print_warning "Step 5: Flushing iptables rules"
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# IPv6
ip6tables -F 2>/dev/null || true
ip6tables -X 2>/dev/null || true
ip6tables -t nat -F 2>/dev/null || true
ip6tables -t nat -X 2>/dev/null || true
ip6tables -t mangle -F 2>/dev/null || true
ip6tables -t mangle -X 2>/dev/null || true

print_status "iptables flushed"

# Step 6: CRITICAL - Remove all ipsets (this is the key step!)
print_warning "Step 6: Destroying all ipsets (including Calico ipsets)"

# First, try to flush and destroy all ipsets
ipset flush 2>/dev/null || true
ipset destroy 2>/dev/null || true

# If that fails, destroy them one by one
if ipset list -n 2>/dev/null | grep -q "cali"; then
    print_warning "Found Calico ipsets, removing individually..."
    for set in $(ipset list -n 2>/dev/null | grep "^cali" || true); do
        print_warning "Destroying ipset: $set"
        # Flush first to remove references
        ipset flush "$set" 2>/dev/null || true
        # Then destroy
        ipset destroy "$set" 2>/dev/null || true
        # If still fails, it's held by kernel - we'll need to unload modules
    done
fi

# Destroy any remaining ipsets
for set in $(ipset list -n 2>/dev/null || true); do
    ipset flush "$set" 2>/dev/null || true
    ipset destroy "$set" 2>/dev/null || true
done

print_status "ipsets destroyed"

# Step 7: CRITICAL - Remove iptables saved rules
print_warning "Step 7: Removing saved iptables rules"
rm -f /etc/iptables/rules.v4 2>/dev/null || true
rm -f /etc/iptables/rules.v6 2>/dev/null || true
rm -f /etc/sysconfig/iptables 2>/dev/null || true
rm -f /etc/sysconfig/ip6tables 2>/dev/null || true
print_status "Saved rules removed"

# Step 8: CRITICAL - Unload kernel modules
print_warning "Step 8: Unloading kernel modules"

# Calico-specific modules
modules=(
    "ipip"
    "vxlan"
    "wireguard"
    "ip_set"
    "ip_set_hash_ip"
    "ip_set_hash_net"
    "xt_set"
    "nf_nat"
    "nf_conntrack"
    "br_netfilter"
    "overlay"
)

for mod in "${modules[@]}"; do
    if lsmod | grep -q "^$mod"; then
        print_warning "Unloading module: $mod"
        rmmod "$mod" 2>/dev/null || true
    fi
done

# Force unload if still present
modprobe -r ipip 2>/dev/null || true
modprobe -r vxlan 2>/dev/null || true
modprobe -r wireguard 2>/dev/null || true
modprobe -r ip_set 2>/dev/null || true
modprobe -r xt_set 2>/dev/null || true

print_status "Kernel modules unloaded"

# Step 9: Remove Calico configuration files
print_warning "Step 9: Removing Calico configuration"
rm -rf /etc/calico
rm -rf /var/lib/calico
rm -rf /var/log/calico
rm -rf /opt/cni/bin/calico
rm -rf /opt/cni/bin/calico-ipam
print_status "Calico configuration removed"

# Step 10: Remove CNI configuration
print_warning "Step 10: Removing CNI configuration"
rm -rf /etc/cni/net.d/*
rm -rf /var/lib/cni
rm -rf /opt/cni/bin/*
print_status "CNI configuration removed"

# Step 11: Clean routing tables
print_warning "Step 11: Cleaning routing tables"

# Remove Calico routes
ip route flush proto bird 2>/dev/null || true
ip route flush proto 80 2>/dev/null || true  # Calico routes

# Clean up route tables
for table in $(seq 1 255); do
    ip route flush table $table 2>/dev/null || true
done

print_status "Routing tables cleaned"

# Step 12: Remove Kubernetes directories
print_warning "Step 12: Removing Kubernetes directories"
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf /var/lib/kube-proxy
rm -rf /var/log/pods
rm -rf /var/log/containers
rm -rf ~/.kube
rm -rf /root/.kube
print_status "Kubernetes directories removed"

# Step 13: Reload modules with clean state
print_warning "Step 13: Reloading network modules with clean state"
modprobe br_netfilter 2>/dev/null || true
modprobe overlay 2>/dev/null || true
print_status "Modules reloaded"

# Step 14: Reload sysctl settings
print_warning "Step 14: Reloading sysctl settings"
sysctl --system 2>/dev/null || true
print_status "Sysctl reloaded"

# Step 15: Verify cleanup
echo ""
print_warning "Step 15: Verification"

# Check ipsets
IPSETS=$(ipset list -n 2>/dev/null | grep -c "^cali" || echo "0")
if [ "$IPSETS" -eq 0 ]; then
    print_status "No Calico ipsets remaining"
else
    print_error "WARNING: $IPSETS Calico ipsets still present"
    ipset list -n | grep "^cali"
fi

# Check interfaces
INTERFACES=$(ip link show | grep -c "cali\|vxlan.calico\|tunl0" || echo "0")
if [ "$INTERFACES" -eq 0 ]; then
    print_status "No Calico interfaces remaining"
else
    print_error "WARNING: Calico interfaces still present"
    ip link show | grep "cali\|vxlan.calico\|tunl0"
fi

# Check modules
if lsmod | grep -q "ipip\|vxlan.*calico"; then
    print_warning "Some Calico modules still loaded (may be needed by system)"
else
    print_status "Calico modules unloaded"
fi

# Check iptables
IPTABLES_RULES=$(iptables-save | grep -c "cali\|KUBE" || echo "0")
if [ "$IPTABLES_RULES" -eq 0 ]; then
    print_status "No Calico/Kubernetes iptables rules"
else
    print_error "WARNING: $IPTABLES_RULES iptables rules still present"
fi

echo ""
echo "=========================================="
echo "Deep Cleanup Complete!"
echo "=========================================="
echo ""
print_warning "Recommendations:"
echo "  1. REBOOT the system now: sudo reboot"
echo "  2. After reboot, verify: ipset list -n | grep cali"
echo "  3. Then reinstall Kubernetes with containerd"
echo ""
print_warning "A REBOOT is HIGHLY recommended to ensure kernel state is clean!"
echo ""

read -p "Reboot now? (yes/no): " reboot_now
if [ "$reboot_now" = "yes" ]; then
    print_status "Rebooting in 5 seconds..."
    sleep 5
    reboot
fi
