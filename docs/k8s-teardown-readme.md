# Kubernetes Uninstall Role

This Ansible role uninstalls and removes Kubernetes (kubeadm-based installation) along with its dependencies from your system.

## Description

This role provides a complete cleanup of Kubernetes installations, including:
- Draining and deleting nodes from the cluster
- Resetting kubeadm configuration
- Removing Kubernetes packages (kubeadm, kubelet, kubectl, kubernetes-cni)
- Removing container runtime (Docker, containerd, or CRI-O)
- Cleaning up configuration directories and files
- Removing CNI plugins
- Cleaning up network interfaces
- Flushing iptables rules
- Removing Helm (optional)
- Removing repository configurations

## Requirements

- Ansible 2.9 or higher
- Root or sudo access on target hosts
- Supported OS: Ubuntu 16.04+, Debian 9+, CentOS 7+, RHEL 7+

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Container runtime used (docker, containerd, crio)
k8s_container_runtime: "docker"

# Whether to remove Helm
k8s_remove_helm: true

# Whether to flush iptables rules
k8s_flush_iptables: true

# Whether to re-enable swap after uninstall
k8s_enable_swap: false

# Whether to reboot after uninstallation
k8s_reboot_after_uninstall: false

# Timeout for drain operation (seconds)
k8s_drain_timeout: 300
```

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
---
- hosts: k8s_nodes
  become: yes
  roles:
    - k8s_uninstall
```

### With Custom Variables

```yaml
---
- hosts: k8s_nodes
  become: yes
  roles:
    - role: k8s_uninstall
      vars:
        k8s_container_runtime: "containerd"
        k8s_remove_helm: true
        k8s_flush_iptables: true
        k8s_reboot_after_uninstall: true
```

### Multi-Node Cluster Uninstallation

For a multi-node cluster, uninstall in this order:

1. Worker nodes first
2. Control plane nodes last

```yaml
---
- name: Uninstall Kubernetes from worker nodes
  hosts: k8s_workers
  become: yes
  serial: 1
  roles:
    - k8s_uninstall

- name: Uninstall Kubernetes from control plane
  hosts: k8s_masters
  become: yes
  serial: 1
  roles:
    - k8s_uninstall
```

### Using with Inventory Groups

```ini
# inventory.ini
[k8s_masters]
master-01 ansible_host=192.168.1.10
master-02 ansible_host=192.168.1.11
master-03 ansible_host=192.168.1.12

[k8s_workers]
worker-01 ansible_host=192.168.1.20
worker-02 ansible_host=192.168.1.21
worker-03 ansible_host=192.168.1.22

[k8s_nodes:children]
k8s_masters
k8s_workers

[k8s_nodes:vars]
ansible_user=ubuntu
ansible_become=yes
```

## What Gets Removed

### Packages
- kubeadm
- kubelet
- kubectl
- kubernetes-cni
- Container runtime packages (Docker/containerd/CRI-O)

### Directories
- `/etc/kubernetes`
- `/etc/cni`
- `/opt/cni`
- `/var/lib/kubelet`
- `/var/lib/kube-proxy`
- `/var/lib/etcd`
- `/var/lib/docker` (if using Docker)
- `/var/lib/containerd` (if using containerd)
- `/var/log/pods`
- `/var/log/containers`
- `/run/flannel`
- `~/.kube`
- `~/.helm` (if k8s_remove_helm is true)

### Network Configuration
- Virtual network interfaces (cni, flannel, docker, veth)
- iptables rules (if k8s_flush_iptables is true)
- ipvs rules

### Services
- kubelet
- docker (if applicable)
- containerd (if applicable)
- crio (if applicable)

## Important Notes

1. **Data Loss**: This role will completely remove Kubernetes and all its data. Make sure to backup any important configurations or data before running.

2. **Multi-node Clusters**: For multi-node clusters, always uninstall worker nodes before control plane nodes to avoid issues.

3. **Network Rules**: The role will flush iptables rules by default. If you have custom iptables rules, either disable this feature or ensure you have them backed up.

4. **Reboot**: Consider setting `k8s_reboot_after_uninstall: true` for a clean system state, especially if you plan to reinstall Kubernetes.

5. **Container Runtime**: Make sure to set `k8s_container_runtime` correctly to match what was installed.

## Safety Features

- The role includes error handling to continue even if some components are not found
- Provides warnings before destructive operations
- Drains nodes gracefully before removal
- Supports idempotent operations (can be run multiple times safely)

## Testing

Test the role in a non-production environment first:

```bash
# Check mode (dry-run)
ansible-playbook -i inventory.ini uninstall_k8s.yml --check

# Verbose mode to see detailed output
ansible-playbook -i inventory.ini uninstall_k8s.yml -v
```

## Troubleshooting

### Issue: Some packages won't uninstall
**Solution**: Run the playbook again with `-vvv` for detailed output. Some packages may have dependencies that need manual resolution.

### Issue: iptables rules persist
**Solution**: Ensure `k8s_flush_iptables: true` is set, or manually flush rules after running the role.

### Issue: Network interfaces remain
**Solution**: Reboot the system to ensure all network interfaces are cleaned up properly.

## Author

Created for O-RAN SC SMO deployment uninstallation.

## License

Apache License 2.0

## Related Roles

- `k8s_setup` - Role for setting up Kubernetes (corresponding installation role)
