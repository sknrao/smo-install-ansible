#!/bin/bash
# Helm post-renderer script for modifying image tags
# This script reads the rendered manifests from stdin, modifies them, and outputs to stdout

set -e

# Configuration file path (can be overridden by environment variable)
CONFIG_FILE="${POST_RENDERER_CONFIG:-/tmp/post-renderer-config.yaml}"

# Read all manifests from stdin
INPUT=$(cat)

# Function to extract all image references using yq
extract_images() {
    local input="$1"
    # Use yq to find all image references in the YAML
    echo "$input" | yq eval '.. | select(has("image")) | .image' - 2>/dev/null | grep -v '^-' || true
}

# Function to apply image mappings
apply_image_mappings() {
    local input="$1"
    local output="$input"
    
    # Check if configuration file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Warning: Configuration file $CONFIG_FILE not found" >&2
        echo "$output"
        return
    fi
    
    # Read mappings from config file
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Parse mapping: old_image:old_tag -> new_image:new_tag
        if [[ "$line" =~ ^([^:]+):([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^:]+):([^[:space:]]+)$ ]]; then
            OLD_IMAGE="${BASH_REMATCH[1]}"
            OLD_TAG="${BASH_REMATCH[2]}"
            NEW_IMAGE="${BASH_REMATCH[3]}"
            NEW_TAG="${BASH_REMATCH[4]}"
            
            # Use yq to replace the image reference properly
            output=$(echo "$output" | yq eval "(.. | select(has(\"image\")) | select(.image == \"${OLD_IMAGE}:${OLD_TAG}\") | .image) = \"${NEW_IMAGE}:${NEW_TAG}\"" - 2>/dev/null || echo "$output")
            
        # Parse tag-only mapping: image_name:old_tag -> new_tag
        elif [[ "$line" =~ ^([^:]+):([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^[:space:]]+)$ ]]; then
            IMAGE_NAME="${BASH_REMATCH[1]}"
            OLD_TAG="${BASH_REMATCH[2]}"
            NEW_TAG="${BASH_REMATCH[3]}"
            
            # Replace only the tag for specific image using yq
            output=$(echo "$output" | yq eval "(.. | select(has(\"image\")) | select(.image | test(\".*${IMAGE_NAME}:${OLD_TAG}.*\")) | .image) |= sub(\":${OLD_TAG}\", \":${NEW_TAG}\")" - 2>/dev/null || echo "$output")
            
        # Parse global tag replacement: *:old_tag -> new_tag
        elif [[ "$line" =~ ^\*:([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^[:space:]]+)$ ]]; then
            OLD_TAG="${BASH_REMATCH[1]}"
            NEW_TAG="${BASH_REMATCH[2]}"
            
            # Replace tag globally for all images using yq
            output=$(echo "$output" | yq eval "(.. | select(has(\"image\")) | .image) |= sub(\":${OLD_TAG}([[:space:]]|$)\", \":${NEW_TAG}\")" - 2>/dev/null || echo "$output")
            
        # Parse wildcard pattern: registry/namespace/*:tag -> new_tag
        elif [[ "$line" =~ ^([^*]+)\*:([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^[:space:]]+)$ ]]; then
            PREFIX="${BASH_REMATCH[1]}"
            OLD_TAG="${BASH_REMATCH[2]}"
            NEW_TAG="${BASH_REMATCH[3]}"
            
            # Replace tag for images matching prefix
            output=$(echo "$output" | yq eval "(.. | select(has(\"image\")) | select(.image | test(\"^${PREFIX}.*:${OLD_TAG}\")) | .image) |= sub(\":${OLD_TAG}\", \":${NEW_TAG}\")" - 2>/dev/null || echo "$output")
            
        # Parse registry replacement: old_registry/* -> new_registry/*
        elif [[ "$line" =~ ^([^*]+)\*[[:space:]]*-\>[[:space:]]*([^*]+)\*$ ]]; then
            OLD_REGISTRY="${BASH_REMATCH[1]}"
            NEW_REGISTRY="${BASH_REMATCH[2]}"
            
            # Replace registry for matching images
            output=$(echo "$output" | yq eval "(.. | select(has(\"image\")) | select(.image | test(\"^${OLD_REGISTRY}\")) | .image) |= sub(\"^${OLD_REGISTRY}\", \"${NEW_REGISTRY}\")" - 2>/dev/null || echo "$output")
        fi
        
    done < "$CONFIG_FILE"
    
    echo "$output"
}

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Warning: yq not found, falling back to sed-based replacements" >&2
    
    # Fallback to basic sed replacement
    OUTPUT="$INPUT"
    
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            
            if [[ "$line" =~ ^([^:]+):([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^:]+):([^[:space:]]+)$ ]]; then
                OLD="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
                NEW="${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
                OUTPUT=$(echo "$OUTPUT" | sed -E "s|image: ${OLD}|image: ${NEW}|g")
            fi
        done < "$CONFIG_FILE"
    fi
    
    echo "$OUTPUT"
else
    # Use yq for proper YAML manipulation
    apply_image_mappings "$INPUT"
fi