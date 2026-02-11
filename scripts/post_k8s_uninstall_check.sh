#!/bin/bash
# Post-uninstall verification script
# Run this after executing the Ansible uninstall role to verify cleanup

set -e

echo "==================================="
echo "Kubernetes Post-Uninstall Verification"
echo "==================================="
echo ""

check_passed=0
check_failed=0

# Function to check if command exists
check_command() {
    if command -v $1 &> /dev/null; then
        echo "✗ $1 is still installed"
        ((check_failed++))
        return 1
    else
        echo "✓ $1 has been removed"
        ((check_passed++))
        return 0
    fi
}

# Function to check if directory exists
check_directory() {
    if [ -d "$1" ]; then
        echo "✗ Directory still exists: $1"
        ((check_failed++))
        return 1
    else
        echo "✓ Directory removed: $1"
        ((check_passed++))
        return 0
    fi
}

# Function to check if service exists
check_service() {
    if systemctl list-unit-files | grep -q "^$1"; then
        echo "✗ Service still exists: $1"
        ((check_failed++))
        return 1
    else
        echo "✓ Service removed: $1"
        ((check_passed++))
        return 0
    fi
}

# Check Kubernetes binaries
echo "Checking Kubernetes binaries..."
check_command kubectl
check_command kubeadm
check_command kubelet
echo ""

# Check container runtimes
echo "Checking container runtimes..."
if ! check_command docker; then
    echo "  Note: Docker removal is optional"
fi
echo ""

# Check Helm
echo "Checking Helm..."
check_command helm
echo ""

# Check Kubernetes directories
echo "Checking Kubernetes directories..."
check_directory "/etc/kubernetes"
check_directory "/var/lib/kubelet"
check_directory "/var/lib/etcd"
check_directory "/etc/cni"
check_directory "/opt/cni"
check_directory "/var/lib/kube-proxy"
echo ""

# Check user directories
echo "Checking user configuration directories..."
check_directory "$HOME/.kube"
check_directory "/root/.kube"
check_directory "$HOME/.helm"
check_directory "/root/.helm"
echo ""

# Check services
echo "Checking Kubernetes services..."
check_service "kubelet.service"
echo ""

# Check processes
echo "Checking running Kubernetes processes..."
k8s_processes=$(ps aux | grep -E 'kube|etcd' | grep -v grep | wc -l)
if [ "$k8s_processes" -gt 0 ]; then
    echo "✗ Found $k8s_processes Kubernetes-related processes still running"
    ps aux | grep -E 'kube|etcd' | grep -v grep
    ((check_failed++))
else
    echo "✓ No Kubernetes processes running"
    ((check_passed++))
fi
echo ""

# Check network interfaces
echo "Checking virtual network interfaces..."
k8s_interfaces=$(ip link show | grep -E 'cni|flannel|docker' | wc -l)
if [ "$k8s_interfaces" -gt 0 ]; then
    echo "✗ Found $k8s_interfaces Kubernetes network interfaces"
    ip link show | grep -E 'cni|flannel|docker'
    ((check_failed++))
else
    echo "✓ No Kubernetes network interfaces found"
    ((check_passed++))
fi
echo ""

# Check iptables rules
echo "Checking iptables rules..."
k8s_iptables=$(sudo iptables -t nat -L | grep -i kube | wc -l)
if [ "$k8s_iptables" -gt 0 ]; then
    echo "⚠ Found $k8s_iptables Kubernetes-related iptables rules"
    echo "  (These may be intentional if you skipped iptables cleanup)"
else
    echo "✓ No Kubernetes iptables rules found"
    ((check_passed++))
fi
echo ""

# Check mounted volumes
echo "Checking mounted Kubernetes volumes..."
k8s_mounts=$(mount | grep -E 'kubelet|kubernetes' | wc -l)
if [ "$k8s_mounts" -gt 0 ]; then
    echo "✗ Found $k8s_mounts Kubernetes-related mounts"
    mount | grep -E 'kubelet|kubernetes'
    ((check_failed++))
else
    echo "✓ No Kubernetes mounts found"
    ((check_passed++))
fi
echo ""

# Check systemd unit files
echo "Checking systemd unit files..."
if [ -f "/etc/systemd/system/kubelet.service" ] || [ -d "/etc/systemd/system/kubelet.service.d" ]; then
    echo "✗ Kubelet systemd files still exist"
    ((check_failed++))
else
    echo "✓ Kubelet systemd files removed"
    ((check_passed++))
fi
echo ""

# Check repository files
echo "Checking repository configurations..."
if [ -f "/etc/apt/sources.list.d/kubernetes.list" ] || [ -f "/etc/yum.repos.d/kubernetes.repo" ]; then
    echo "✗ Kubernetes repository configuration still exists"
    ((check_failed++))
else
    echo "✓ Kubernetes repository configuration removed"
    ((check_passed++))
fi
echo ""

# Summary
echo "==================================="
echo "Post-Uninstall Verification Summary"
echo "==================================="
echo "Checks passed: $check_passed"
echo "Checks failed: $check_failed"
echo ""

if [ "$check_failed" -eq 0 ]; then
    echo "✓ SUCCESS: Kubernetes has been completely removed!"
    echo ""
    echo "Recommendations:"
    echo "  - Consider rebooting the system for a clean state"
    echo "  - Review any remaining iptables rules if needed"
    echo "  - Check disk space with 'df -h' to confirm cleanup"
    exit 0
else
    echo "⚠ WARNING: Some components were not completely removed"
    echo ""
    echo "Recommendations:"
    echo "  - Review the failed checks above"
    echo "  - Run the uninstall role again if needed"
    echo "  - Consider manual cleanup of remaining components"
    echo "  - Reboot the system to clear remaining processes"
    exit 1
fi
