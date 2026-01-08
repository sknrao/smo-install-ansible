# Image Mappings Data Flow - Step by Step

## Complete Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User Configuration (variables)                                │
│    - image_mappings_file: "/opt/smo/image-mappings.txt"         │
│    - image_tag_mappings: ["inline:mapping1", "inline:mapping2"] │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. install.yml - Read External File (if specified)               │
│                                                                   │
│    - name: Read mappings from file                               │
│      slurp:                                                       │
│        src: "{{ image_mappings_file }}"                          │
│      register: mappings_content                                  │
│                                                                   │
│    Result: mappings_content.content = "base64encodedcontent"    │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. install.yml - Parse and Decode File Content                   │
│                                                                   │
│    - name: Parse mappings from file                              │
│      set_fact:                                                    │
│        file_based_mappings: "{{ (mappings_content.content |     │
│                                 b64decode).split('\n') |         │
│                                 select('match', '^[^#].*') |     │
│                                 select() | list }}"              │
│                                                                   │
│    Result: file_based_mappings = ["mapping1", "mapping2", ...]  │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. install.yml - Combine Inline + File Mappings                  │
│                                                                   │
│    - name: Combine inline and file-based mappings               │
│      set_fact:                                                    │
│        effective_image_mappings: "{{ image_tag_mappings +       │
│                                     (file_based_mappings |       │
│                                      default([])) }}"            │
│                                                                   │
│    Result: effective_image_mappings = all mappings combined     │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. install.yml - Generate Config File from Template              │
│                                                                   │
│    - name: Generate post-renderer configuration                 │
│      template:                                                    │
│        src: post-renderer-config.yaml.j2                        │
│        dest: "{{ post_renderer_config }}"                       │
│                                                                   │
│    Template uses: {{ effective_image_mappings }}                │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│ 6. post-renderer-config.yaml.j2 - Write Mappings                │
│                                                                   │
│    {% for mapping in effective_image_mappings %}                │
│    {{ mapping }}                                                 │
│    {% endfor %}                                                  │
│                                                                   │
│    Output: /tmp/post-renderer-config.yaml                       │
│    Content:                                                      │
│      nexus3.onap.org:10001/onap/aai:1.12.3 -> harbor.local/... │
│      nexus3.onap.org:10001/onap/sdc:1.10.2 -> harbor.local/... │
│      ... (all mappings)                                          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│ 7. Helm Deployment with Post-Renderer                            │
│                                                                   │
│    helm deploy onap onap/onap \                                  │
│      --post-renderer {{ post_renderer_script }}                 │
│                                                                   │
│    Environment: POST_RENDERER_CONFIG=/tmp/post-renderer-config.yaml │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│ 8. helm-post-renderer.sh - Read Config and Apply Mappings        │
│                                                                   │
│    CONFIG_FILE="${POST_RENDERER_CONFIG}"                        │
│    while IFS= read -r line; do                                   │
│        # Parse each mapping line and apply with yq              │
│    done < "$CONFIG_FILE"                                         │
└─────────────────────────────────────────────────────────────────┘
```

## File Content Example

### Input: /opt/smo/image-mappings.txt
```text
# ONAP Components
nexus3.onap.org:10001/onap/aai:1.12.3 -> harbor.local/onap/aai:1.12.3
nexus3.onap.org:10001/onap/sdc:1.10.2 -> harbor.local/onap/sdc:1.10.2
nexus3.onap.org:10001/onap/policy-api:2.8.2 -> harbor.local/onap/policy-api:2.8.2
```

### After slurp (base64 encoded):
```json
{
  "content": "IyBPTkFQIENvbXBvbmVudHMKbmV4dXMzLm9uYXAub3JnOjEwMDAxL29u...",
  "encoding": "base64"
}
```

### After b64decode and parse (file_based_mappings):
```yaml
[
  "nexus3.onap.org:10001/onap/aai:1.12.3 -> harbor.local/onap/aai:1.12.3",
  "nexus3.onap.org:10001/onap/sdc:1.10.2 -> harbor.local/onap/sdc:1.10.2",
  "nexus3.onap.org:10001/onap/policy-api:2.8.2 -> harbor.local/onap/policy-api:2.8.2"
]
```

### After combining with inline mappings (effective_image_mappings):
```yaml
[
  "onap/aai:latest -> onap/aai:stable",           # From inline
  "nexus3.onap.org:10001/onap/aai:1.12.3 -> harbor.local/onap/aai:1.12.3",  # From file
  "nexus3.onap.org:10001/onap/sdc:1.10.2 -> harbor.local/onap/sdc:1.10.2",  # From file
  "nexus3.onap.org:10001/onap/policy-api:2.8.2 -> harbor.local/onap/policy-api:2.8.2"  # From file
]
```

### Final output: /tmp/post-renderer-config.yaml
```yaml
# Helm Post-Renderer Configuration
# Mappings from inline variable or external file
onap/aai:latest -> onap/aai:stable
nexus3.onap.org:10001/onap/aai:1.12.3 -> harbor.local/onap/aai:1.12.3
nexus3.onap.org:10001/onap/sdc:1.10.2 -> harbor.local/onap/sdc:1.10.2
nexus3.onap.org:10001/onap/policy-api:2.8.2 -> harbor.local/onap/policy-api:2.8.2
```

## Key Variables at Each Stage

| Stage | Variable Name | Type | Content |
|-------|--------------|------|---------|
| User input | `image_mappings_file` | string | "/opt/smo/image-mappings.txt" |
| User input | `image_tag_mappings` | list | ["inline:map1", "inline:map2"] |
| After slurp | `mappings_content.content` | base64 string | "IyBPTkFQIENv..." |
| After decode | `file_based_mappings` | list | ["file:map1", "file:map2", ...] |
| After combine | `effective_image_mappings` | list | All mappings combined |
| In template | `effective_image_mappings` | list | Used in Jinja2 loop |
| Final config | N/A | text file | /tmp/post-renderer-config.yaml |

## How Template Consumes effective_image_mappings

### post-renderer-config.yaml.j2:
```jinja2
# Mappings from inline variable or external file
{% if effective_image_mappings is defined and effective_image_mappings | length > 0 %}
{% for mapping in effective_image_mappings %}
{{ mapping }}
{% endfor %}
{% endif %}
```

This loops through the `effective_image_mappings` list and writes each mapping as a line in the config file.

## Summary

The `image_mappings_file` is:
1. ✅ Read by Ansible using `slurp` module (returns base64)
2. ✅ Decoded using `b64decode` filter
3. ✅ Split into lines and filtered (remove comments/empty)
4. ✅ Stored in `file_based_mappings` variable
5. ✅ Combined with `image_tag_mappings` into `effective_image_mappings`
6. ✅ Passed to Jinja2 template as `effective_image_mappings`
7. ✅ Written to `/tmp/post-renderer-config.yaml` by template
8. ✅ Read by `helm-post-renderer.sh` script during Helm deployment

The key is that the template receives `effective_image_mappings` which contains ALL mappings (both inline and from file), not the raw file path.