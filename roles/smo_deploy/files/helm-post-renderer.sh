#!/bin/bash
# Helm post-renderer script for modifying image tags
# This script reads the rendered manifests from stdin, modifies them, and outputs to stdout

set -e

# Configuration file path (can be overridden by environment variable)
CONFIG_FILE="${POST_RENDERER_CONFIG:-/tmp/post-renderer-config.yaml}"

# Read all manifests from stdin
MANIFESTS=$(cat)

# Function to modify image tags
modify_image_tags() {
    local input="$1"
    local output="$input"
    
    # Check if configuration file exists
    if [ -f "$CONFIG_FILE" ]; then
        # Read image tag mappings from config file
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            
            # Parse mapping: old_image:old_tag -> new_image:new_tag
            if [[ "$line" =~ ^([^:]+):([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^:]+):([^[:space:]]+)$ ]]; then
                OLD_IMAGE="${BASH_REMATCH[1]}"
                OLD_TAG="${BASH_REMATCH[2]}"
                NEW_IMAGE="${BASH_REMATCH[3]}"
                NEW_TAG="${BASH_REMATCH[4]}"
                
                # Replace image and tag
                output=$(echo "$output" | sed -E "s|image: ${OLD_IMAGE}:${OLD_TAG}|image: ${NEW_IMAGE}:${NEW_TAG}|g")
                
            # Parse tag-only mapping: image_name:old_tag -> new_tag
            elif [[ "$line" =~ ^([^:]+):([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^[:space:]]+)$ ]]; then
                IMAGE_NAME="${BASH_REMATCH[1]}"
                OLD_TAG="${BASH_REMATCH[2]}"
                NEW_TAG="${BASH_REMATCH[3]}"
                
                # Replace only the tag for specific image
                output=$(echo "$output" | sed -E "s|(image: .*${IMAGE_NAME}):${OLD_TAG}|\1:${NEW_TAG}|g")
                
            # Parse global tag replacement: *:old_tag -> new_tag
            elif [[ "$line" =~ ^\*:([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^[:space:]]+)$ ]]; then
                OLD_TAG="${BASH_REMATCH[1]}"
                NEW_TAG="${BASH_REMATCH[2]}"
                
                # Replace tag globally for all images
                output=$(echo "$output" | sed -E "s|:${OLD_TAG}([[:space:]]|$)|:${NEW_TAG}\1|g")
            fi
        done < "$CONFIG_FILE"
    fi
    
    echo "$output"
}

# Apply modifications
MODIFIED_MANIFESTS=$(modify_image_tags "$MANIFESTS")

# Output modified manifests
echo "$MODIFIED_MANIFESTS"