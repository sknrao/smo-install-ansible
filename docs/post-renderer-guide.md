# Helm Post-Renderer for Image Tag Modification

## Overview

The post-renderer allows you to modify Docker image tags in Helm charts during deployment without changing the chart source code. This is useful for:

- Using different image registries
- Pinning specific image versions
- Using custom/patched images
- Air-gapped deployments with local registry
- Testing with different image versions

## How It Works

The post-renderer is a script that:
1. Receives rendered Kubernetes manifests from Helm (via stdin)
2. Modifies image references based on configuration
3. Outputs modified manifests (via stdout)
4. Helm applies the modified manifests to the cluster

## Setup

### 1. Directory Structure

```
roles/smo_deploy/
├── files/
│   └── helm-post-renderer.sh        # Post-renderer script
└── templates/
    └── post-renderer-config.yaml.j2 # Configuration template
```

### 2. Enable Post-Renderer

In your playbook or defaults/main.yml:

```yaml
enable_post_renderer: true
```

## Configuration Methods

### Method 1: Simple Global Tag Replacement

Replace all 'latest' tags with a specific version:

```yaml
enable_post_renderer: true
global_image_tag: "stable"
```

This changes:
- `onap/aai:latest` → `onap/aai:stable`
- `o-ran-sc/nonrtric:latest` → `o-ran-sc/nonrtric:stable`

### Method 2: Component-Specific Tags

Override tags for specific components:

```yaml
enable_post_renderer: true
onap_image_tag: "2.8.0"
nonrtric_image_tag: "1.2.3"
```

This changes:
- All ONAP images: `onap/*:*` → `onap/*:2.8.0`
- All Non-RT RIC images: `o-ran-sc/*:*` → `o-ran-sc/*:1.2.3`

### Method 3: Custom Image Mappings

For precise control, use image_tag_mappings:

```yaml
enable_post_renderer: true
image_tag_mappings:
  # Change complete image reference
  - "nexus3.onap.org:10001/onap/aai:1.12.3 -> myregistry.com/onap/aai:1.12.4"
  
  # Change only tag for specific image
  - "policy-apex-pdp:latest -> policy-apex-pdp:2.8.2"
  
  # Global tag replacement
  - "*:latest -> stable"
  
  # Change registry only
  - "nexus3.onap.org:10001/onap/sdnc:2.5.1 -> harbor.mycompany.com/onap/sdnc:2.5.1"
```

## Configuration Syntax

### Format Options

1. **Full Image Replacement:**
   ```
   old_registry/old_image:old_tag -> new_registry/new_image:new_tag
   ```
   Example: `nexus3.onap.org:10001/onap/aai:1.0.0 -> myregistry.com/onap/aai:1.0.1`

2. **Tag-Only Change:**
   ```
   image_name:old_tag -> new_tag
   ```
   Example: `policy-apex-pdp:latest -> policy-apex-pdp:2.8.2`

3. **Global Tag Replacement:**
   ```
   *:old_tag -> new_tag
   ```
   Example: `*:latest -> stable`

4. **Wildcard Patterns:**
   ```
   registry/namespace/*:old_tag -> new_tag
   ```
   Example: `onap/*:* -> 2.8.0`

## Usage Examples

### Example 1: Air-Gapped Deployment

Use local registry for all images:

```yaml
enable_post_renderer: true
image_tag_mappings:
  - "nexus3.onap.org:10001/* -> harbor.local:5000/*"
  - "docker.io/* -> harbor.local:5000/*"
  - "o-ran-sc/* -> harbor.local:5000/o-ran-sc/*"
```

### Example 2: Pin Specific Versions

Lock down image versions for production:

```yaml
enable_post_renderer: true
image_tag_mappings:
  - "onap/aai:* -> onap/aai:1.12.3"
  - "onap/sdc:* -> onap/sdc:1.10.2"
  - "onap/sdnc:* -> onap/sdnc:2.5.1"
  - "policy-apex-pdp:* -> policy-apex-pdp:2.8.2"
```

### Example 3: Use Custom Patched Images

Replace specific images with patched versions:

```yaml
enable_post_renderer: true
image_tag_mappings:
  - "onap/aai:1.12.3 -> myregistry.com/onap/aai:1.12.3-patch1"
  - "onap/sdnc:2.5.1 -> myregistry.com/onap/sdnc:2.5.1-custom"
```

### Example 4: Mixed Strategy

Combine multiple approaches:

```yaml
enable_post_renderer: true
global_image_tag: "stable"  # Default to stable
image_tag_mappings:
  # Except for these specific overrides
  - "onap/aai:* -> onap/aai:1.12.4"
  - "nexus3.onap.org:10001/* -> harbor.local:5000/*"
```

## Deployment with Post-Renderer

### Basic Deployment

```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "enable_post_renderer=true" \
  -e "global_image_tag=stable"
```

### Advanced Deployment

```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e "enable_post_renderer=true" \
  -e '{"image_tag_mappings": [
    "nexus3.onap.org:10001/* -> harbor.local:5000/*",
    "onap/aai:* -> onap/aai:1.12.4"
  ]}'
```

### Using Variables File

Create `post-renderer-vars.yml`:

```yaml
enable_post_renderer: true
global_image_tag: "stable"
onap_image_tag: "2.8.0"
image_tag_mappings:
  - "nexus3.onap.org:10001/onap/aai:* -> harbor.local:5000/onap/aai:1.12.4"
  - "policy-apex-pdp:latest -> policy-apex-pdp:2.8.2"
```

Deploy:

```bash
ansible-playbook -i inventory.ini deploy-smo.yml \
  -e @post-renderer-vars.yml
```

## Verification

### 1. Check Post-Renderer Configuration

After deployment starts, check the generated config:

```bash
cat /tmp/post-renderer-config.yaml
```

### 2. Verify Image Tags in Deployed Pods

```bash
kubectl get pods -n onap -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
```

### 3. Check Specific Deployment

```bash
kubectl get deployment <deployment-name> -n onap -o jsonpath='{.spec.template.spec.containers[*].image}'
```

## Troubleshooting

### Post-Renderer Not Working

1. **Check script is executable:**
   ```bash
   ls -la /opt/o-ran-sc/it-dep/helm-post-renderer.sh
   ```

2. **Verify configuration exists:**
   ```bash
   cat /tmp/post-renderer-config.yaml
   ```

3. **Test post-renderer manually:**
   ```bash
   helm template onap onap/onap | /opt/o-ran-sc/it-dep/helm-post-renderer.sh | grep "image:"
   ```

### Images Not Being Modified

1. **Check pattern syntax:**
   Make sure wildcards and patterns match your images exactly.

2. **Enable debugging:**
   Add to helm-post-renderer.sh:
   ```bash
   set -x  # Enable debug mode
   echo "Processing image modifications..." >&2
   ```

3. **View rendered manifests:**
   ```bash
   helm template onap onap/onap --post-renderer /opt/o-ran-sc/it-dep/helm-post-renderer.sh > rendered.yaml
   grep "image:" rendered.yaml
   ```

### Syntax Errors in Config

Common issues:
- Missing spaces around `->`
- Wrong wildcard patterns
- Incorrect image names

Valid:
```
onap/aai:1.0.0 -> onap/aai:1.0.1
```

Invalid:
```
onap/aai:1.0.0->onap/aai:1.0.1  # Missing spaces
```

## Advanced Configuration

### Custom Post-Renderer Script

If you need more complex logic, modify `helm-post-renderer.sh`:

```bash
# Add custom transformations
# Example: Add imagePullPolicy
output=$(echo "$output" | sed '/image:/a\      imagePullPolicy: Always')
```

### Multiple Configuration Files

Use different configs for different components:

```yaml
# In install.yml
environment:
  POST_RENDERER_CONFIG: "{{ post_renderer_config }}_{{ item }}"
loop:
  - onap
  - nonrtric
```

### Conditional Post-Rendering

Enable only for specific components:

```yaml
# In playbook
- name: Deploy ONAP with post-renderer
  include_role:
    name: smo_deploy
  vars:
    enable_post_renderer: true
    deploy_nonrtric: false

- name: Deploy Non-RT RIC without post-renderer  
  include_role:
    name: smo_deploy
  vars:
    enable_post_renderer: false
    deploy_onap: false
    deploy_nonrtric: true
```

## Security Considerations

1. **Script Permissions:**
   The post-renderer script runs with the same permissions as Helm.
   
2. **Config File Location:**
   Keep configuration in a secure location:
   ```yaml
   post_renderer_config: "/etc/smo/post-renderer-config.yaml"
   ```

3. **Registry Credentials:**
   If using private registries, ensure image pull secrets are configured:
   ```bash
   kubectl create secret docker-registry regcred \
     --docker-server=harbor.local:5000 \
     --docker-username=admin \
     --docker-password=password
   ```

## Best Practices

1. **Test First:**
   Always test post-renderer with `helm template` before deployment.

2. **Document Mappings:**
   Keep a record of image modifications for troubleshooting.

3. **Version Control:**
   Store post-renderer configuration in git.

4. **Use Specific Tags:**
   Avoid using `latest` - pin to specific versions.

5. **Minimal Changes:**
   Only modify what's necessary to reduce complexity.

6. **Validate Images:**
   Ensure replacement images exist before deployment:
   ```bash
   docker pull harbor.local:5000/onap/aai:1.12.4
   ```

## References

- [Helm Post-Rendering Documentation](https://helm.sh/docs/topics/advanced/#post-rendering)
- [O-RAN SMO Installation Guide](https://docs.o-ran-sc.org/)