# SMO Uninstall Ansible Role

This Ansible role automates the uninstallation of SMO (Service Management and Orchestration) components from a Kubernetes cluster.

## Description

This role performs a complete cleanup of SMO-related components including:
- ONAP (Open Network Automation Platform)
- NonRTRIC (Non-Real-Time RAN Intelligent Controller)
- Strimzi Kafka
- MariaDB Operator
- OpenEBS storage
- Associated namespaces, PersistentVolumes, and StorageClasses

## Requirements

- Ansible 2.9 or higher
- Python dependencies:
  - kubernetes
  - openshift
  - PyYAML
- kubectl configured with access to the target Kubernetes cluster
- helm CLI installed on the control node
- Sufficient privileges to delete Kubernetes resources

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Timeout values in seconds
namespace_deletion_timeout: 600
helm_uninstall_timeout: 300

# Namespaces to clean up
smo_namespaces:
  - onap
  - strimzi-system
  - mariadb-operator
  - nonrtric
  - smo
  - openebs

# NonRTRIC PersistentVolumes
nonrtric_pvs:
  - nonrtric-pv1
  - nonrtric-pv2
  - nonrtric-pv3

# Storage paths to clean
storage_paths:
  - /dockerdata-nfs
  - /dockerdata

# StorageClass configuration
smo_storage_class_name: smo-storage

# Helm release configuration
helm_release_name: oran-nonrtric
helm_release_namespace: nonrtric

# OpenEBS configuration
openebs_release_name: openebs
openebs_namespace: openebs

# Whether to ignore errors during cleanup
ignore_cleanup_errors: yes
```

## Dependencies

This role requires the following Ansible collections:
- `kubernetes.core`

Install with:
```bash
ansible-galaxy collection install kubernetes.core
```

## Example Playbook

Basic usage:

```yaml
---
- hosts: kubernetes_master
  become: yes
  roles:
    - role: smo-uninstall
```

With custom variables:

```yaml
---
- hosts: kubernetes_master
  become: yes
  roles:
    - role: smo-uninstall
      vars:
        namespace_deletion_timeout: 900
        ignore_cleanup_errors: no
```

## Execution Order

The role executes the following task files in order:

1. **prerequisites.yml** - Ensures jq is installed
2. **cleanup_onap.yml** - Removes ONAP components and namespaces
3. **cleanup_nonrtric.yml** - Removes NonRTRIC components including Kong cleanup
4. **cleanup_smo.yml** - Removes SMO namespace
5. **cleanup_storage.yml** - Removes storage classes, OpenEBS, and local storage directories
6. **cleanup_final.yml** - Performs verification and displays cleanup status

## Safety Features

- Uses `ignore_errors: yes` on most tasks to ensure the playbook continues even if resources don't exist
- Includes timeout values for namespace deletion to prevent hanging
- Provides verification steps at the end to show remaining resources
- Waits for namespace deletion to complete before proceeding

## Important Notes

1. **Destructive Operation**: This role permanently deletes all SMO-related resources
2. **Data Loss**: All data in `/dockerdata-nfs` and `/dockerdata` directories will be removed
3. **Kong Cleanup**: Automatically detects if Kong was installed and performs cleanup
4. **PersistentVolumes**: Released PVs are automatically cleaned up after each major component removal

## Post-Uninstall Verification

After the role completes, it will:
- List any remaining SMO-related namespaces
- Display any remaining PersistentVolumes
- Show cleanup completion message

## Troubleshooting

If namespaces remain in "Terminating" state:
```bash
# Check for finalizers
kubectl get namespace <namespace-name> -o json | jq '.spec.finalizers'

# Remove finalizers if needed
kubectl patch namespace <namespace-name> -p '{"spec":{"finalizers":[]}}' --type=merge
```

If PersistentVolumes remain:
```bash
# Check PV status
kubectl get pv

# Manually delete if needed
kubectl delete pv <pv-name>
```

## License

Apache-2.0

## Author Information

This role was created for the O-RAN Software Community (o-ran-sc) IT/Dep project.

Based on the uninstall scripts from: https://github.com/o-ran-sc/it-dep/tree/master/smo-install
