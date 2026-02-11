#!/bin/bash
# Pre-uninstall verification script
# Run this before executing the Ansible uninstall role

set -e

echo "==================================="
echo "Kubernetes Pre-Uninstall Verification"
echo "==================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "✗ kubectl is not installed or not in PATH"
    echo "  This might indicate Kubernetes is already removed or not properly installed."
    exit 0
fi

echo "✓ kubectl is available"
echo ""

# Check cluster status
echo "Checking cluster status..."
if kubectl cluster-info &> /dev/null; then
    echo "✓ Cluster is reachable"
    echo ""
    
    # Display nodes
    echo "Current nodes in the cluster:"
    kubectl get nodes -o wide
    echo ""
    
    # Display running pods
    echo "Pods running in the cluster:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Running | wc -l
    echo ""
    
    # Check for persistent volumes
    echo "Persistent Volumes:"
    pv_count=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
    echo "  Count: $pv_count"
    if [ "$pv_count" -gt 0 ]; then
        echo "  WARNING: There are $pv_count PVs that will be lost!"
        kubectl get pv
    fi
    echo ""
    
    # Check for important namespaces
    echo "Important namespaces found:"
    for ns in ricplt ricinfra ricaux kube-system; do
        if kubectl get namespace $ns &> /dev/null; then
            pod_count=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l)
            echo "  - $ns ($pod_count pods)"
        fi
    done
    echo ""
    
else
    echo "✗ Cluster is not reachable"
    echo "  Node might not be part of a cluster or cluster is down."
    echo ""
fi

# Check container runtime
echo "Checking container runtime..."
if command -v docker &> /dev/null; then
    echo "✓ Docker is installed"
    running_containers=$(docker ps -q | wc -l)
    echo "  Running containers: $running_containers"
fi

if command -v crictl &> /dev/null; then
    echo "✓ CRI-O/containerd (crictl) is available"
    running_containers=$(crictl ps -q 2>/dev/null | wc -l || echo "0")
    echo "  Running containers: $running_containers"
fi
echo ""

# Check disk usage
echo "Checking disk usage of Kubernetes directories..."
if [ -d "/var/lib/kubelet" ]; then
    kubelet_size=$(du -sh /var/lib/kubelet 2>/dev/null | cut -f1)
    echo "  /var/lib/kubelet: $kubelet_size"
fi

if [ -d "/var/lib/docker" ]; then
    docker_size=$(du -sh /var/lib/docker 2>/dev/null | cut -f1)
    echo "  /var/lib/docker: $docker_size"
fi

if [ -d "/var/lib/containerd" ]; then
    containerd_size=$(du -sh /var/lib/containerd 2>/dev/null | cut -f1)
    echo "  /var/lib/containerd: $containerd_size"
fi

if [ -d "/var/lib/etcd" ]; then
    etcd_size=$(du -sh /var/lib/etcd 2>/dev/null | cut -f1)
    echo "  /var/lib/etcd: $etcd_size"
fi
echo ""

# Check for Helm releases
if command -v helm &> /dev/null; then
    echo "Checking Helm releases..."
    helm_count=$(helm list --all-namespaces 2>/dev/null | grep -v NAME | wc -l)
    echo "  Active Helm releases: $helm_count"
    if [ "$helm_count" -gt 0 ]; then
        echo "  WARNING: These Helm releases will be lost!"
        helm list --all-namespaces
    fi
    echo ""
fi

# Summary
echo "==================================="
echo "Pre-Uninstall Check Complete"
echo "==================================="
echo ""
echo "⚠️  WARNING: Proceeding with uninstallation will:"
echo "   - Remove ALL Kubernetes components"
echo "   - Delete ALL cluster data"
echo "   - Remove ALL containers and images"
echo "   - Delete ALL persistent volumes"
echo "   - Remove ALL Helm releases"
echo ""
echo "Make sure you have:"
echo "   ✓ Backed up any important data"
echo "   ✓ Exported any necessary configurations"
echo "   ✓ Documented any custom settings"
echo ""
read -p "Do you want to proceed with the uninstallation? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Uninstallation cancelled."
    exit 1
fi

echo "Proceeding with uninstallation..."
