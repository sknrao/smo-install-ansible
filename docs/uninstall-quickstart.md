# SMO Uninstall - Quick Start Guide

## Prerequisites

1. **Install Ansible** (if not already installed):
```bash
sudo apt update
sudo apt install -y ansible
```

2. **Install required Python packages**:
```bash
pip3 install kubernetes openshift PyYAML
```

3. **Install required Ansible collections**:
```bash
ansible-galaxy collection install -r requirements.yml
```

## Directory Structure

```
.
├── smo-uninstall/                 # Ansible role directory
│   ├── defaults/
│   │   └── main.yml              # Default variables
│   ├── meta/
│   │   └── main.yml              # Role metadata
│   ├── tasks/
│   │   ├── main.yml              # Main task orchestration
│   │   ├── prerequisites.yml     # Install prerequisites (jq)
│   │   ├── cleanup_onap.yml      # ONAP cleanup tasks
│   │   ├── cleanup_nonrtric.yml  # NonRTRIC cleanup tasks
│   │   ├── cleanup_smo.yml       # SMO cleanup tasks
│   │   ├── cleanup_storage.yml   # Storage cleanup tasks
│   │   └── cleanup_final.yml     # Final verification
│   └── README.md                 # Role documentation
├── smo_uninstall_playbook.yml    # Example playbook
├── inventory.ini                  # Inventory file (edit this)
└── requirements.yml               # Ansible collection requirements
```

## Usage

### Step 1: Configure Inventory

Edit `inventory.ini` and update with your Kubernetes master node details:

```ini
[kubernetes_master]
k8s-master ansible_host=YOUR_K8S_MASTER_IP ansible_user=YOUR_USERNAME
```

### Step 2: Test Connectivity

```bash
ansible -i inventory.ini kubernetes_master -m ping
```

### Step 3: Run the Uninstallation

```bash
ansible-playbook -i inventory.ini smo_uninstall_playbook.yml
```

### Step 4: Run in Check Mode (Dry Run)

To see what would be changed without making actual changes:

```bash
ansible-playbook -i inventory.ini smo_uninstall_playbook.yml --check
```

### Step 5: Run with Verbose Output

For detailed execution logs:

```bash
ansible-playbook -i inventory.ini smo_uninstall_playbook.yml -v
# or -vv, -vvv for more verbosity
```

## Advanced Usage

### Running Specific Tasks

To run only specific cleanup tasks, use tags:

```bash
# Only cleanup ONAP
ansible-playbook -i inventory.ini smo_uninstall_playbook.yml --tags onap

# Only cleanup storage
ansible-playbook -i inventory.ini smo_uninstall_playbook.yml --tags storage
```

Note: Tags need to be added to the task files if you want to use this feature.

### Skip Confirmation Prompt

To skip the interactive confirmation:

```bash
ansible-playbook -i inventory.ini smo_uninstall_playbook.yml \
  --extra-vars "ansible_check_mode=true"
```

### Custom Variables

Override default variables:

```bash
ansible-playbook -i inventory.ini smo_uninstall_playbook.yml \
  --extra-vars "namespace_deletion_timeout=900 ignore_cleanup_errors=no"
```

## Verification

After the playbook completes, verify the cleanup:

```bash
# Check for remaining namespaces
kubectl get namespaces | grep -E 'onap|nonrtric|smo|strimzi|mariadb'

# Check for remaining PersistentVolumes
kubectl get pv

# Check storage directories (on K8s master node)
sudo ls -la /dockerdata-nfs /dockerdata
```

## Troubleshooting

### Namespace Stuck in "Terminating" State

```bash
# View namespace status
kubectl get namespace <namespace-name> -o yaml

# Remove finalizers if stuck
kubectl patch namespace <namespace-name> \
  -p '{"spec":{"finalizers":[]}}' --type=merge
```

### PersistentVolume Cleanup Issues

```bash
# Check PV details
kubectl describe pv <pv-name>

# Force delete if needed
kubectl patch pv <pv-name> -p '{"metadata":{"finalizers":null}}'
kubectl delete pv <pv-name> --grace-period=0 --force
```

### Helm Release Issues

```bash
# List all helm releases
helm list --all-namespaces

# Manually delete if needed
helm delete <release-name> -n <namespace>
```

### Collection Not Found Error

```bash
# Install kubernetes.core collection
ansible-galaxy collection install kubernetes.core

# Or install all requirements
ansible-galaxy collection install -r requirements.yml --force
```

## Common Issues

1. **kubectl not configured**: Ensure kubectl is configured on the Ansible control node with access to the cluster
2. **Insufficient permissions**: Run with become/sudo privileges
3. **Timeout errors**: Increase timeout values in defaults/main.yml
4. **Module not found**: Install required Python packages and Ansible collections

## Safety Notes

⚠️ **WARNING**: This playbook will:
- Delete all SMO-related namespaces and resources
- Remove all data from /dockerdata-nfs and /dockerdata directories
- Delete all associated PersistentVolumes
- Uninstall OpenEBS

Make sure you have:
- Backed up any important data
- Confirmed this is the correct cluster
- Notified all stakeholders

## Support

For issues or questions:
- Check the role README.md for detailed documentation
- Review the O-RAN-SC IT/Dep project: https://github.com/o-ran-sc/it-dep
- Consult the original uninstall scripts in smo-install directory
