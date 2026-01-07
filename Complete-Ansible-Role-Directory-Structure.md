# Complete Ansible Role Directory Structure

## Full Directory Tree

```
smo-ansible-deployment/
├── inventory.ini                           # Server inventory
├── deploy-smo.yml                          # Main deployment playbook
├── uninstall-smo.yml                       # Uninstall playbook
├── deploy-with-post-renderer-examples.yml  # Post-renderer examples
├── ansible.cfg                             # Ansible configuration (optional)
│
└── roles/
    └── smo_deploy/
        ├── defaults/
        │   └── main.yml                    # ✅ Default variables (UPDATED with post-renderer)
        │
        ├── files/
        │   └── helm-post-renderer.sh       # ✅ NEW - Post-renderer script
        │
        ├── templates/
        │   └── post-renderer-config.yaml.j2 # ✅ NEW - Post-renderer config template
        │
        ├── tasks/
        │   ├── main.yml                    # Task orchestrator
        │   ├── preflight.yml               # Pre-flight checks
        │   ├── cluster.yml                 # Kubernetes cluster setup
        │   ├── preconfigure.yml            # Pre-deployment configuration
        │   ├── helm_prep.yml               # Helm and plugin setup
        │   ├── prepull_images.yml          # Image pre-pulling
        │   ├── install.yml                 # ✅ SMO installation (UPDATED with post-renderer)
        │   ├── postconfigure.yml           # Post-deployment configuration
        │   └── verify.yml                  # Verification
        │
        ├── handlers/
        │   └── main.yml                    # Handlers (optional, can be minimal)
        │
        └── meta/
            └── main.yml                    # Role metadata (optional)
```

## Files to Create/Update

### New Files for Post-Renderer:

1. **roles/smo_deploy/files/helm-post-renderer.sh**
   - Artifact: `post_renderer_script`
   - Executable script that modifies image tags

2. **roles/smo_deploy/templates/post-renderer-config.yaml.j2**
   - Artifact: `post_renderer_config`
   - Jinja2 template for post-renderer configuration

### Updated Files:

3. **roles/smo_deploy/defaults/main.yml**
   - Artifact: `defaults_main` (UPDATED)
   - Now includes post-renderer variables

4. **roles/smo_deploy/tasks/install.yml**
   - Artifact: `task_install` (UPDATED)
   - Now includes post-renderer setup and usage

### All Other Files (Unchanged):

5. **inventory.ini** - Artifact: `inventory_file`
6. **deploy-smo.yml** - Artifact: `playbook_deploy`
7. **uninstall-smo.yml** - Artifact: `uninstall_playbook`
8. **tasks/main.yml** - Artifact: `tasks_main`
9. **tasks/preflight.yml** - Artifact: `task_preflight`
10. **tasks/cluster.yml** - Artifact: `task_cluster`
11. **tasks/preconfigure.yml** - Artifact: `task_preconfigure`
12. **tasks/helm_prep.yml** - Artifact: `task_helm_prep`
13. **tasks/prepull_images.yml** - Artifact: `task_prepull`
14. **tasks/postconfigure.yml** - Artifact: `task_postconfigure`
15. **tasks/verify.yml** - Artifact: `task_verify`

### New Example Files:

16. **deploy-with-post-renderer-examples.yml** - Artifact: `post_renderer_examples`
17. **POST_RENDERER_GUIDE.md** - Artifact: `post_renderer_guide`

## Quick Setup Script

```bash
#!/bin/bash
# setup-smo-ansible.sh

# Create directory structure
mkdir -p smo-ansible-deployment/roles/smo_deploy/{defaults,files,templates,tasks,handlers,meta}
cd smo-ansible-deployment

# Create minimal handlers/main.yml
cat > roles/smo_deploy/handlers/main.yml <<'EOF'
---
# Handlers for SMO deployment
- name: restart microk8s
  command: microk8s stop && microk8s start
  listen: "restart cluster"
EOF

# Create minimal meta/main.yml
cat > roles/smo_deploy/meta/main.yml <<'EOF'
---
galaxy_info:
  role_name: smo_deploy
  author: O-RAN SC
  description: Deploy O-RAN SMO with post-renderer support
  license: Apache-2.0
  min_ansible_version: "2.10"
  platforms:
    - name: Ubuntu
      versions:
        - focal
        - jammy
dependencies: []
EOF

echo "Directory structure created successfully!"
echo ""
echo "Next steps:"
echo "1. Copy all artifact files to their respective locations"
echo "2. Make helm-post-renderer.sh executable:"
echo "   chmod +x roles/smo_deploy/files/helm-post-renderer.sh"
echo "3. Update inventory.ini with your server details"
echo "4. Run: ansible-playbook -i inventory.ini deploy-smo.yml"
```

## File Checklist

Use this checklist to ensure all files are in place:

```
✅ Core Structure
  ✅ inventory.ini
  ✅ deploy-smo.yml
  ✅ uninstall-smo.yml
  ✅ roles/smo_deploy/defaults/main.yml (UPDATED)

✅ Post-Renderer (NEW)
  ✅ roles/smo_deploy/files/helm-post-renderer.sh
  ✅ roles/smo_deploy/templates/post-renderer-config.yaml.j2

✅ Task Files
  ✅ roles/smo_deploy/tasks/main.yml
  ✅ roles/smo_deploy/tasks/preflight.yml
  ✅ roles/smo_deploy/tasks/cluster.yml
  ✅ roles/smo_deploy/tasks/preconfigure.yml
  ✅ roles/smo_deploy/tasks/helm_prep.yml
  ✅ roles/smo_deploy/tasks/prepull_images.yml
  ✅ roles/smo_deploy/tasks/install.yml (UPDATED)
  ✅ roles/smo_deploy/tasks/postconfigure.yml
  ✅ roles/smo_deploy/tasks/verify.yml

✅ Optional Files
  ✅ roles/smo_deploy/handlers/main.yml
  ✅ roles/smo_deploy/meta/main.yml
  ✅ deploy-with-post-renderer-examples.yml
```

## Post-Renderer Specific Setup

After creating the directory structure:

### 1. Make Post-Renderer Script Executable

```bash
chmod +x roles/smo_deploy/files/helm-post-renderer.sh
```

### 2. Verify Script Syntax

```bash
bash -n roles/smo_deploy/files/helm-post-renderer.sh
```

### 3. Test Post-Renderer (Optional)

```bash
# Create test config
cat > /tmp/test-post-renderer.yaml <<EOF
onap/aai:latest -> onap/aai:stable
*:latest -> 2.8.0
EOF

# Test with sample manifest
echo 'image: onap/aai:latest' | \
  POST_RENDERER_CONFIG=/tmp/test-post-renderer.yaml \
  roles/smo_deploy/files/helm-post-renderer.sh
```

Expected output: `image: onap/aai:stable`

## Deployment Examples

### Basic Deployment (No Post-Renderer)

```bash
ansible-playbook -i inventory.ini deploy-smo.yml
```

### With Post-Renderer (Global Tag)

```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "enable_post_renderer=true" \
  -e "global_image_tag=stable"
```

### With Post-Renderer (Custom Mappings)

```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "enable_post_renderer=true" \
  -e '{"image_tag_mappings": ["onap/aai:* -> onap/aai:1.12.4"]}'
```

### Using Example Playbooks

```bash
# Run specific example
ansible-playbook -i inventory.ini deploy-with-post-renderer-examples.yml \
  --tags "example1"
```

## Verification

After deployment, verify post-renderer worked:

```bash
# Check configuration was created
cat /tmp/post-renderer-config.yaml

# Check deployed image tags
kubectl get pods -n onap -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Check specific deployment
kubectl get deployment onap-aai -n onap -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Troubleshooting

### Post-Renderer Not Found

```bash
# Check file exists
ls -la /opt/o-ran-sc/it-dep/helm-post-renderer.sh

# Check permissions
stat /opt/o-ran-sc/it-dep/helm-post-renderer.sh
```

### Configuration Not Applied

```bash
# Verify config file
cat /tmp/post-renderer-config.yaml

# Test manually
helm template onap onap/onap | \
  POST_RENDERER_CONFIG=/tmp/post-renderer-config.yaml \
  /opt/o-ran-sc/it-dep/helm-post-renderer.sh | grep "image:"
```

## Next Steps

1. ✅ Create directory structure
2. ✅ Copy all artifact files
3. ✅ Make helm-post-renderer.sh executable
4. ✅ Update inventory.ini
5. ✅ Configure post-renderer variables (if needed)
6. ✅ Run deployment
7. ✅ Verify image tags

For detailed post-renderer usage, see **POST_RENDERER_GUIDE.md**