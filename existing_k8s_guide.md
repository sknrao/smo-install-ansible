# Using Existing Kubernetes Cluster Guide

This guide explains how to use the SMO Ansible role with an existing Kubernetes cluster instead of MicroK8s.

## Prerequisites

### 1. Kubernetes Cluster Requirements

- **Kubernetes Version:** 1.23+
- **Access:** kubectl configured with cluster-admin privileges
- **Nodes:** Minimum 3 nodes (or 1 for testing)
- **Resources per node:**
  - CPU: 8+ cores
  - Memory: 32GB+
  - Disk: 100GB+

### 2. Required Components

- **kubectl** installed and configured
- **Helm 3** (will be installed by the role if missing)
- **Container runtime:** containerd, docker, or cri-o
- **Storage class:** Default storage class configured
- **Ingress controller:** Optional but recommended

### 3. Network Requirements

- Pods can communicate across nodes
- Services accessible via ClusterIP
- External access via NodePort or LoadBalancer (for external services)

## Configuration Steps

### Step 1: Update defaults/main.yml

```yaml
# Cluster Configuration
cluster_type: "existing"  # Changed from "microk8s"
kubectl_command: "kubectl"  # Standard kubectl
container_runtime: "containerd"  # or "docker" or "cri-o"
ctr_command: "crictl"  # or "docker" based on runtime

# Storage Configuration
storage_class: "standard"  # Your cluster's storage class name
# Common options: "standard", "nfs-client", "longhorn", "local-path", "ceph-rbd"

# Disable MicroK8s-specific features
configure_persistent_storage: false  # Assuming storage is already configured
```

### Step 2: Replace cluster.yml Task File

Replace `roles/smo_deploy/tasks/cluster.yml` with the version for existing clusters:

- Use the artifact: `task_cluster_k8s`
- This version:
  - Skips MicroK8s installation
  - Verifies kubectl connectivity
  - Checks cluster readiness
  - Validates storage class availability

### Step 3: Update Variable References

The role now uses these variables throughout:

```yaml
{{ kubectl_command }}   # Instead of hardcoded "microk8s kubectl"
{{ ctr_command }}       # Instead of hardcoded "microk8s ctr"
{{ storage_class }}     # Instead of hardcoded "microk8s-hostpath"
```

## Quick Conversion

### Option 1: Use the Conversion Script

```bash
# Run the conversion script
chmod +x convert-to-kubectl.sh
./convert-to-kubectl.sh

# Review changes
git diff

# Commit if satisfied
git add -A
git commit -m "Convert to use existing Kubernetes cluster"
```

### Option 2: Manual Conversion

Replace the following files with their K8s-compatible versions:

1. **roles/smo_deploy/tasks/cluster.yml** → Use `task_cluster_k8s`
2. **roles/smo_deploy/tasks/preconfigure.yml** → Use `task_preconfigure_k8s`
3. **roles/smo_deploy/tasks/prepull_images.yml** → Use `task_prepull_k8s`
4. **roles/smo_deploy/defaults/main.yml** → Use `defaults_main_k8s`

Then in remaining files, replace:
```bash
# Find and replace in all task files
find roles/smo_deploy/tasks/ -name "*.yml" -exec sed -i 's/microk8s kubectl/{{ kubectl_command }}/g' {} \;
find roles/smo_deploy/tasks/ -name "*.yml" -exec sed -i 's/microk8s ctr/{{ ctr_command }}/g' {} \;
find . -name "*.yml" -exec sed -i 's/microk8s-hostpath/{{ storage_class | default("standard") }}/g' {} \;
```

## Storage Class Configuration

### Finding Your Storage Class

```bash
# List available storage classes
kubectl get storageclass

# Find default storage class
kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
```

### Common Storage Classes

| Provider | Storage Class Name | Notes |
|----------|-------------------|-------|
| AWS EKS | `gp2`, `gp3` | EBS volumes |
| GKE | `standard`, `standard-rwo` | Persistent Disk |
| AKS | `default`, `managed-premium` | Azure Disk |
| Bare Metal | `local-path`, `nfs-client` | Local or NFS storage |
| Longhorn | `longhorn` | Cloud-native storage |
| Rook/Ceph | `rook-ceph-block` | Distributed storage |

### Configure in Variables

```yaml
# In your playbook or defaults/main.yml
storage_class: "gp3"  # For AWS
# or
storage_class: "standard-rwo"  # For GKE
# or
storage_class: "nfs-client"  # For NFS provisioner
```

## Container Runtime Detection

The role auto-detects your container runtime:

```yaml
# Containerd (most common)
container_runtime: "containerd"
ctr_command: "crictl"

# Docker
container_runtime: "docker"
ctr_command: "docker"

# CRI-O
container_runtime: "cri-o"
ctr_command: "crictl"
```

### Verify Container Runtime

```bash
# Check what's installed
kubectl get nodes -o wide

# Check container runtime on node
ssh <node> "ps aux | grep -E 'containerd|dockerd|crio'"

# For containerd
crictl version

# For docker
docker version
```

## Deployment Examples

### Example 1: AWS EKS Cluster

```yaml
# inventory.ini
[smo_servers]
k8s-master ansible_host=<master-ip> ansible_user=ubuntu

# deploy-smo.yml variables
vars:
  cluster_type: "existing"
  kubectl_command: "kubectl"
  storage_class: "gp3"
  container_runtime: "containerd"
  ctr_command: "crictl"
  deployment_flavor: "default"
```

### Example 2: On-Premises Cluster with NFS

```yaml
vars:
  cluster_type: "existing"
  kubectl_command: "kubectl"
  storage_class: "nfs-client"
  container_runtime: "containerd"
  ctr_command: "crictl"
  external_ip: "192.168.1.100"
```

### Example 3: Minikube (Testing)

```yaml
vars:
  cluster_type: "existing"
  kubectl_command: "kubectl"
  storage_class: "standard"
  container_runtime: "docker"
  ctr_command: "docker"
  deployment_flavor: "small"
  min_cpu_cores: 4
  min_memory_gb: 16
```

### Example 4: RKE/Rancher Cluster

```yaml
vars:
  cluster_type: "existing"
  kubectl_command: "kubectl"
  storage_class: "longhorn"
  container_runtime: "containerd"
  ctr_command: "crictl"
  ingress_enabled: true
```

## Verification Before Deployment

### 1. Check Cluster Access

```bash
kubectl cluster-info
kubectl get nodes
kubectl auth can-i '*' '*' --all-namespaces  # Should return "yes"
```

### 2. Verify Storage

```bash
kubectl get storageclass
kubectl describe storageclass <your-storage-class>
```

### 3. Test Storage Provisioning

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: <your-storage-class>
EOF

kubectl get pvc test-pvc
kubectl delete pvc test-pvc
```

### 4. Check Container Runtime

```bash
# On cluster nodes
kubectl get nodes -o wide

# SSH to node and check
crictl version  # For containerd
# or
docker version  # For docker
```

## Deployment Command

```bash
# With existing cluster
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "cluster_type=existing" \
  -e "kubectl_command=kubectl" \
  -e "storage_class=your-storage-class"
```

## Troubleshooting

### Issue 1: kubectl Not Found

```bash
# Verify kubectl is in PATH
which kubectl
kubectl version

# If not installed, install it:
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### Issue 2: No Storage Class

```bash
# Check if any storage class exists
kubectl get sc

# If none, you need to install a storage provisioner
# For local testing, use local-path-provisioner:
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml

# Set as default:
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Issue 3: Permission Denied

```bash
# Check current user permissions
kubectl auth can-i '*' '*' --all-namespaces

# If not cluster-admin, create ClusterRoleBinding:
kubectl create clusterrolebinding <user>-cluster-admin \
  --clusterrole=cluster-admin \
  --user=<your-user>
```

### Issue 4: Container Runtime Issues

```bash
# If crictl not found but containerd is running:
sudo apt-get install -y cri-tools

# Configure crictl:
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF
```

### Issue 5: Image Pull Fails

If using containerd and images fail to pull:

```bash
# Check containerd config
sudo cat /etc/containerd/config.toml

# Ensure registry configs are present
# Restart containerd
sudo systemctl restart containerd
```

## Differences from MicroK8s Deployment

| Feature | MicroK8s | Existing Cluster |
|---------|----------|------------------|
| kubectl command | `microk8s kubectl` | `kubectl` |
| Container runtime | `microk8s ctr` | `crictl` or `docker` |
| Storage class | `microk8s-hostpath` | Your cluster's SC |
| Cluster setup | Automated by role | Pre-existing |
| Addons | Enabled via microk8s | Pre-configured |
| Ingress | MicroK8s ingress | Your ingress controller |

## Best Practices

1. **Use a dedicated namespace:** Keep ONAP in `onap` namespace
2. **Resource quotas:** Set quotas to prevent resource exhaustion
3. **Network policies:** Implement network segmentation
4. **Monitoring:** Deploy Prometheus/Grafana for observability
5. **Backup:** Regular backup of PVCs and configurations
6. **High availability:** Use multiple replicas for critical components
7. **Storage:** Ensure sufficient storage capacity for logs and data

## Next Steps

After configuring for existing cluster:

1. ✅ Update `defaults/main.yml`
2. ✅ Replace cluster.yml with K8s version
3. ✅ Verify kubectl access
4. ✅ Configure storage class
5. ✅ Test with syntax check: `ansible-playbook deploy-smo.yml --syntax-check`
6. ✅ Deploy: `ansible-playbook -i inventory.ini deploy-smo.yml`

## Support Matrix

| K8s Distribution | Supported | Storage Class Options |
|------------------|-----------|----------------------|
| Vanilla K8s | ✅ Yes | local-path, nfs-client, longhorn |
| AWS EKS | ✅ Yes | gp2, gp3, efs |
| Google GKE | ✅ Yes | standard, standard-rwo |
| Azure AKS | ✅ Yes | default, managed-premium |
| RKE/Rancher | ✅ Yes | longhorn, local-path |
| K3s | ✅ Yes | local-path |
| Minikube | ✅ Yes (testing) | standard |
| MicroK8s | ✅ Yes | microk8s-hostpath |
| OpenShift | ⚠️ Untested | gp2, ceph-rbd |

For OpenShift, you may need additional adjustments for SecurityContextConstraints (SCC).