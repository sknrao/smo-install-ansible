#!/bin/bash
# Complete Kubernetes cleanup script
# Run this with sudo to ensure complete cleanup

set -e

echo "=========================================="
echo "Complete Kubernetes Cleanup Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# 1. Stop all Kubernetes processes
print_warning "Stopping all Kubernetes processes..."

# Kill kubelet and related processes
pkill -9 kubelet 2>/dev/null || true
pkill -9 kube-proxy 2>/dev/null || true
pkill -9 kube-apiserver 2>/dev/null || true
pkill -9 kube-controller 2>/dev/null || true
pkill -9 kube-scheduler 2>/dev/null || true
pkill -9 etcd 2>/dev/null || true

sleep 2
print_status "Kubernetes processes stopped"

# 2. Stop containerd/docker services
print_warning "Stopping container runtime services..."

systemctl stop kubelet 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true
systemctl stop docker 2>/dev/null || true
systemctl stop crio 2>/dev/null || true

sleep 2
print_status "Container runtime services stopped"

# 3. Kill any remaining container processes
print_warning "Killing remaining container processes..."

pkill -9 containerd 2>/dev/null || true
pkill -9 containerd-shim 2>/dev/null || true
pkill -9 dockerd 2>/dev/null || true
pkill -9 docker-proxy 2>/dev/null || true

sleep 2
print_status "Container processes killed"

# 4. Unmount kubelet volumes
print_warning "Unmounting kubelet volumes..."

# Find and unmount all kubelet mounts
for mount in $(cat /proc/mounts | grep '/var/lib/kubelet' | awk '{print $2}'); do
    umount -f "$mount" 2>/dev/null || umount -l "$mount" 2>/dev/null || true
done

# Unmount any remaining container mounts
for mount in $(cat /proc/mounts | grep -E 'kubelet|kubernetes|pods' | awk '{print $2}'); do
    umount -f "$mount" 2>/dev/null || umount -l "$mount" 2>/dev/null || true
done

print_status "Kubelet volumes unmounted"

# 5. Remove Kubernetes directories
print_warning "Removing Kubernetes directories..."

directories=(
    "/etc/kubernetes"
    "/var/lib/kubelet"
    "/var/lib/etcd"
    "/var/lib/kube-proxy"
    "/var/log/pods"
    "/var/log/containers"
    "/run/flannel"
    "/etc/systemd/system/kubelet.service.d"
    "/etc/cni"
    "/opt/cni"
)

for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        print_status "Removed $dir"
    fi
done

# 6. Remove configuration files
print_warning "Removing configuration files..."

files=(
    "/etc/systemd/system/kubelet.service"
    "/usr/lib/systemd/system/kubelet.service"
    "$HOME/.kube"
    "/root/.kube"
)

for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        rm -rf "$file"
        print_status "Removed $file"
    fi
done

# 7. Clean up containerd properly
print_warning "Cleaning up containerd..."

# Stop containerd again
systemctl stop containerd 2>/dev/null || true
sleep 2

# Remove containerd data
rm -rf /var/lib/containerd
rm -rf /run/containerd
rm -rf /var/run/containerd

# Recreate containerd directory structure
mkdir -p /var/lib/containerd
mkdir -p /run/containerd
mkdir -p /etc/containerd

# Generate default containerd config
if command -v containerd &> /dev/null; then
    containerd config default > /etc/containerd/config.toml
    
    # Enable SystemdCgroup
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    
    print_status "Containerd configuration reset"
fi

# 8. Remove network interfaces
print_warning "Removing network interfaces..."

interfaces=$(ip link show | grep -oE '(cni|flannel|docker|veth)[^:@]+' || true)
for iface in $interfaces; do
    ip link delete "$iface" 2>/dev/null || true
    print_status "Removed interface: $iface"
done

# Remove CNI bridge
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
ip link delete docker0 2>/dev/null || true

# 9. Flush iptables rules
print_warning "Flushing iptables rules..."

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X

# Clear ipvs rules if ipvsadm is available
if command -v ipvsadm &> /dev/null; then
    ipvsadm --clear 2>/dev/null || true
fi

print_status "iptables rules flushed"

# 10. Clean up DNS/resolv.conf if modified
print_warning "Checking DNS configuration..."

if grep -q "nameserver 10.96.0.10" /etc/resolv.conf 2>/dev/null; then
    sed -i '/nameserver 10.96.0.10/d' /etc/resolv.conf
    print_status "Removed Kubernetes DNS from resolv.conf"
fi

# 11. Remove systemd drop-ins
print_warning "Cleaning systemd configuration..."

rm -rf /etc/systemd/system/kubelet.service.d
rm -f /etc/systemd/system/kubelet.service

# 12. Reload systemd
systemctl daemon-reload
print_status "Systemd reloaded"

# 13. Restart containerd with clean config
print_warning "Restarting containerd..."

if systemctl is-enabled containerd &>/dev/null; then
    systemctl enable containerd
    systemctl restart containerd
    
    # Wait for containerd to be ready
    sleep 5
    
    # Verify containerd is working
    if systemctl is-active containerd &>/dev/null; then
        print_status "Containerd restarted successfully"
        
        # Test CRI endpoint
        if crictl version &>/dev/null; then
            print_status "CRI endpoint is responding"
        else
            print_warning "CRI endpoint may not be ready yet (this is usually okay)"
        fi
    else
        print_error "Containerd failed to start"
    fi
fi

# 14. Check for processes using Kubernetes ports
print_warning "Checking for processes using Kubernetes ports..."

ports=(6443 10250 10257 10259 2379 2380)
ports_in_use=0

for port in "${ports[@]}"; do
    if lsof -i :$port &>/dev/null; then
        print_warning "Port $port is still in use:"
        lsof -i :$port || true
        ports_in_use=$((ports_in_use + 1))
    fi
done

if [ $ports_in_use -eq 0 ]; then
    print_status "All Kubernetes ports are free"
else
    print_warning "$ports_in_use Kubernetes ports are still in use"
    echo ""
    echo "To kill processes on these ports, run:"
    for port in "${ports[@]}"; do
        echo "  lsof -ti:$port | xargs kill -9"
    done
fi

# 15. Final verification
echo ""
echo "=========================================="
echo "Cleanup Summary"
echo "=========================================="

# Check if kubelet is still running
if pgrep kubelet &>/dev/null; then
    print_error "kubelet is still running"
else
    print_status "kubelet is not running"
fi

# Check if containerd is running
if systemctl is-active containerd &>/dev/null; then
    print_status "containerd is running (ready for reinstall)"
else
    print_warning "containerd is not running"
fi

# Check for Kubernetes directories
k8s_dirs_exist=0
for dir in "/etc/kubernetes" "/var/lib/kubelet" "/var/lib/etcd"; do
    if [ -d "$dir" ]; then
        print_warning "Directory still exists: $dir"
        k8s_dirs_exist=$((k8s_dirs_exist + 1))
    fi
done

if [ $k8s_dirs_exist -eq 0 ]; then
    print_status "All Kubernetes directories removed"
fi

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""

if [ $ports_in_use -gt 0 ]; then
    echo "⚠️  WARNING: Some ports are still in use."
    echo "   You may need to reboot or manually kill processes."
    echo ""
fi

echo "Next steps:"
echo "  1. Verify containerd is working: systemctl status containerd"
echo "  2. Test CRI endpoint: crictl version"
echo "  3. If issues persist, consider rebooting: sudo reboot"
echo "  4. Then retry your Kubernetes installation"
echo ""
