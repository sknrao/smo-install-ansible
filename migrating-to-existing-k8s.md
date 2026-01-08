# Quick Migration Guide: MicroK8s → Existing Kubernetes

## Summary

Yes, you're right! The main change is replacing `microk8s kubectl` with `kubectl`, but there are a few additional considerations.

## What Needs to Change

### 1. **Core Changes (Required)**

| From | To | Where |
|------|-----|-------|
| `microk8s kubectl` | `kubectl` or `{{ kubectl_command }}` | All task files |
| `microk8s ctr` | `crictl` or `{{ ctr_command }}` | prepull_images.yml |
| `microk8s-hostpath` | Your storage class | preconfigure.yml, install.yml |
| `microk8s enable` | Remove/comment | cluster.yml |

### 2. **Configuration Changes**

In `defaults/main.yml`:
```yaml
# OLD:
cluster_type: "microk8s"

# NEW:
cluster_type: "existing"
kubectl_command: "kubectl"
storage_class: "standard"  # or your cluster's storage class
container_runtime: "containerd"  # or docker
ctr_command: "crictl"  # or docker
```

### 3. **Files to Replace**

Replace these with K8s-compatible versions:

1. **roles/smo_deploy/tasks/cluster.yml** 
   - OLD: Installs MicroK8s, enables addons
   - NEW: Verifies existing cluster, checks connectivity

2. **roles/smo_deploy/defaults/main.yml**
   - Add K8s-specific variables

3. **roles/smo_deploy/tasks/preconfigure.yml** (Optional)
   - Use `{{ kubectl_command }}` instead of hardcoded commands

4. **roles/smo_deploy/tasks/prepull_images.yml** (Optional)
   - Support multiple container runtimes

## Quick Migration Options

### Option 1: Automated (Recommended)

```bash
# 1. Download the conversion script
# (Use the artifact: convert_to_kubectl)

chmod +x convert-to-kubectl.sh
./convert-to-kubectl.sh

# 2. Replace cluster.yml
cp /path/to/task_cluster_k8s.yml roles/smo_deploy/tasks/cluster.yml

# 3. Update defaults/main.yml
# Add these variables:
cat >> roles/smo_deploy/defaults/main.yml <<EOF

# Existing Kubernetes Configuration
cluster_type: "existing"
kubectl_command: "kubectl"
storage_class: "standard"
container_runtime: "containerd"
ctr_command: "crictl"
EOF

# 4. Verify
ansible-playbook deploy-smo.yml --syntax-check
```

### Option 2: Manual (If you prefer)

```bash
# 1. Find and replace in all files
find roles/smo_deploy/tasks/ -name "*.yml" -type f -exec sed -i 's/microk8s kubectl/kubectl/g' {} \;
find roles/smo_deploy/tasks/ -name "*.yml" -type f -exec sed -i 's/microk8s ctr/crictl/g' {} \;
find roles/smo_deploy/tasks/ -name "*.yml" -type f -exec sed -i 's/microk8s-hostpath/standard/g' {} \;

# 2. Comment out MicroK8s-specific tasks
sed -i 's/microk8s enable/# microk8s enable/g' roles/smo_deploy/tasks/cluster.yml
sed -i 's/microk8s status/# microk8s status/g' roles/smo_deploy/tasks/cluster.yml

# 3. Update defaults/main.yml
# Add the variables manually

# 4. Replace cluster.yml
# Use the new version that doesn't install MicroK8s
```

## Minimal Changes Approach

If you want the **absolute minimum** changes:

### Just replace these strings globally:

```bash
# In your repo root
grep -rl "microk8s kubectl" roles/smo_deploy/ | xargs sed -i 's/microk8s kubectl/kubectl/g'
grep -rl "microk8s ctr" roles/smo_deploy/ | xargs sed -i 's/microk8s ctr/crictl/g'
grep -rl "microk8s-hostpath" roles/smo_deploy/ | xargs sed -i 's/microk8s-hostpath/standard/g'
```

### Update cluster.yml:

Replace the entire `roles/smo_deploy/tasks/cluster.yml` with a minimal version:

```yaml
---
# Minimal cluster.yml for existing K8s

- name: Clone it-dep repository
  git:
    repo: "{{ it_dep_repo }}"
    dest: "{{ it_dep_dir }}"
    version: "{{ it_dep_branch }}"
    force: yes
  tags: cluster

- name: Verify kubectl works
  command: kubectl cluster-info
  register: cluster_info
  tags: cluster

- name: Create ONAP namespace
  command: kubectl create namespace {{ onap_namespace }}
  register: ns_result
  failed_when: ns_result.rc != 0 and 'AlreadyExists' not in ns_result.stderr
  changed_when: ns_result.rc == 0
  tags: cluster
```

## What About Storage Class?

Find your storage class:
```bash
kubectl get storageclass
```

Then either:

**Option A:** Replace globally
```bash
sed -i 's/microk8s-hostpath/YOUR-STORAGE-CLASS/g' roles/smo_deploy/tasks/*.yml
```

**Option B:** Use variable (better)
```yaml
# In defaults/main.yml
storage_class: "standard"  # Your storage class name

# In task files, use:
storageClassName: {{ storage_class }}
```

## Verification Checklist

Before deploying:

- [ ] `kubectl` command works
- [ ] Can access cluster: `kubectl cluster-info`
- [ ] Have cluster-admin access: `kubectl auth can-i '*' '*' --all-namespaces`
- [ ] Storage class exists: `kubectl get sc`
- [ ] No references to `microk8s` commands remain: `grep -r "microk8s" roles/`
- [ ] Syntax check passes: `ansible-playbook deploy-smo.yml --syntax-check`

## Quick Test

```bash
# Test your changes
ansible-playbook -i inventory.ini deploy-smo.yml --check --diff

# If that looks good, deploy to test environment
ansible-playbook -i inventory.ini deploy-smo.yml -e "deployment_flavor=small"
```

## Summary of Artifacts You Need

For existing Kubernetes support, get these artifacts:

1. **task_cluster_k8s** - New cluster.yml
2. **defaults_main_k8s** - Updated defaults/main.yml
3. **task_preconfigure_k8s** - Updated preconfigure.yml (optional)
4. **task_prepull_k8s** - Updated prepull_images.yml (optional)
5. **convert_to_kubectl** - Conversion script
6. **existing_k8s_guide** - Full guide

## Most Common Issues

### Issue: "microk8s: command not found"
**Fix:** You missed replacing some microk8s commands
```bash
grep -r "microk8s" roles/smo_deploy/tasks/
```

### Issue: Storage class not found
**Fix:** Update storage class name
```bash
kubectl get sc  # Find your storage class
# Then update in your variables
```

### Issue: Permission denied
**Fix:** Ensure you have cluster-admin
```bash
kubectl auth can-i '*' '*' --all-namespaces
```

## Bottom Line

**Yes, you're mostly right!** The main changes are:
1. Replace `microk8s kubectl` → `kubectl` 
2. Replace `microk8s ctr` → `crictl` (or `docker`)
3. Replace `microk8s-hostpath` → your storage class
4. Replace cluster.yml (remove MicroK8s installation)
5. Add a few config variables

The conversion script I provided does most of this automatically! 🎉