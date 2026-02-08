# O-RAN SMO Ansible Deployment Guide

## Quick Start

### 1. Directory Structure

Create the following directory structure:

```
smo-ansible-deployment/
├── inventory.ini                    # Your inventory file
├── deploy-smo.yml                   # Main deployment playbook
├── uninstall-smo.yml               # Uninstall playbook
├── ansible.cfg                      # Ansible configuration (optional)
└── roles/
    └── smo_deploy/
        ├── defaults/
        │   └── main.yml            # Default variables
        ├── tasks/
        │   ├── main.yml            # Main task orchestrator
        │   ├── preflight.yml       # Pre-flight checks
        │   ├── cluster.yml         # Kubernetes cluster setup
        │   ├── preconfigure.yml    # Pre-deployment configuration
        │   ├── helm_prep.yml       # Helm and plugin setup
        │   ├── prepull_images.yml  # Image pre-pulling
        │   ├── install.yml         # SMO installation
        │   ├── postconfigure.yml   # Post-deployment configuration
        │   └── verify.yml          # Verification
        ├── handlers/
        │   └── main.yml            # Handlers
        ├── templates/              # Templates (if needed)
        └── meta/
            └── main.yml            # Role metadata
```

### 2. Get All Task Files

You need to download all the task files from the previous artifact. Here's how to extract them:

**All task files are in the large artifact I created earlier. Let me provide a download script:**

```bash
#!/bin/bash
# save this as extract-role.sh

mkdir -p roles/smo_deploy/{defaults,tasks,handlers,meta,templates}

# The complete role files are in the artifact "smo_role_structure"
# You'll need to manually copy each section from that artifact
# or I can create individual files for you
```

### 3. Minimum Required Files

At minimum, you need these files to get started:

1. **inventory.ini** - I've created this ✅
2. **deploy-smo.yml** - I've created this ✅
3. **uninstall-smo.yml** - I've created this ✅
4. **roles/smo_deploy/defaults/main.yml** - I've created this ✅
5. **roles/smo_deploy/tasks/main.yml** - I've created this ✅
6. **roles/smo_deploy/tasks/*.yml** - All in the smo_role_structure artifact

## Step-by-Step Setup

### Step 1: Create Directory Structure

```bash
mkdir -p smo-ansible-deployment/roles/smo_deploy/{defaults,tasks,handlers,meta}
cd smo-ansible-deployment
```

### Step 2: Create Inventory File

Create `inventory.ini`:
```ini
[smo_servers]
smo-node-1 ansible_host=YOUR_SERVER_IP ansible_user=ubuntu

[smo_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

### Step 3: Get All Task Files

The complete role is in the artifact I created. You need to extract these files:

**From artifact "smo_role_structure":**
- `roles/smo_deploy/tasks/preflight.yml`
- `roles/smo_deploy/tasks/cluster.yml`
- `roles/smo_deploy/tasks/preconfigure.yml`
- `roles/smo_deploy/tasks/helm_prep.yml`
- `roles/smo_deploy/tasks/prepull_images.yml`
- `roles/smo_deploy/tasks/install.yml`
- `roles/smo_deploy/tasks/postconfigure.yml`
- `roles/smo_deploy/tasks/verify.yml`
- `roles/smo_deploy/handlers/main.yml`
- `roles/smo_deploy/meta/main.yml`

### Step 4: Update Variables

Edit `roles/smo_deploy/defaults/main.yml` and set:
- `external_ip`: Your server's external IP
- `deployment_flavor`: Choose from default, small, medium, large
- `deployment_mode`: release, snapshot, or latest

### Step 5: Deploy

```bash
# Test connection
ansible -i inventory.ini smo_servers -m ping

# Run deployment
ansible-playbook -i inventory.ini deploy-smo.yml

# With specific flavor
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "deployment_flavor=small" \
  -e "deployment_mode=release"
```

## Alternative: Download Complete Role as Archive

Since the complete role is quite large, here's how to package it:

**Option 1: From the artifact**
1. Copy all content from the "smo_role_structure" artifact
2. Split it into individual files based on the `# File:` markers
3. Save each file to its correct location

**Option 2: Create a script to extract**

```bash
#!/bin/bash
# extract-role-files.sh

# This script would parse the artifact and create individual files
# You'll need to copy the artifact content and parse it
```

## Quick Deployment (Testing)

For quick testing, you can use inline variables:

```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "external_ip=192.168.1.100" \
  -e "deployment_flavor=small" \
  -e "deploy_oran_components=false" \
  -e "prepull_images=true"
```

## Deployment Options

### Small Testing Environment
```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "deployment_flavor=small" \
  -e "min_cpu_cores=4" \
  -e "min_memory_gb=16"
```

### Production Deployment
```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "deployment_flavor=large" \
  -e "run_smoke_tests=true" \
  -e "configure_integration=true"
```

### Skip Image Pre-pull
```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  --skip-tags prepull
```

### Run Only Specific Phases
```bash
# Only cluster setup
ansible-playbook -i inventory.ini deploy-smo.yml --tags cluster

# Only helm preparation
ansible-playbook -i inventory.ini deploy-smo.yml --tags helm

# Only installation
ansible-playbook -i inventory.ini deploy-smo.yml --tags install
```

## Uninstall

```bash
ansible-playbook -i inventory.ini uninstall-smo.yml

# With PVC cleanup
ansible-playbook -i inventory.ini uninstall-smo.yml \
  -e "cleanup_pvcs=true"
```

## Troubleshooting

### View Deployment Logs
```bash
# On the target server
cat /opt/o-ran-sc/it-dep/smo-deployment-info.txt
cat /opt/o-ran-sc/it-dep/smo-credentials.txt
cat /opt/o-ran-sc/it-dep/smo-image-pull-report.txt
```

### Check Pods
```bash
kubectl get pods -n onap
kubectl get svc -n onap
helm list -n onap
```

### Re-run Failed Deployment
```bash
# With cleanup
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "force_reinstall=true" \
  -e "cleanup_on_failure=true"
```

## Getting Individual Files

Since you mentioned you don't see the final YAML files, I've now created separate artifacts for:

1. ✅ `defaults/main.yml` 
2. ✅ `tasks/main.yml`
3. ✅ `deploy-smo.yml` (main playbook)
4. ✅ `inventory.ini`
5. ✅ `uninstall-smo.yml`

**For the remaining task files**, they are all in the `smo_role_structure` artifact. Would you like me to:
1. Create each task file as a separate artifact? 
2. Provide a script to extract them?
3. Create a downloadable archive?

Let me know which approach works best for you!