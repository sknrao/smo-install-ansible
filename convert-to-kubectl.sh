#!/bin/bash
# Script to convert microk8s kubectl commands to standard kubectl
# This helps when using an existing Kubernetes cluster instead of MicroK8s

set -e

ROLES_DIR="roles/smo_deploy"

echo "Converting microk8s kubectl to kubectl in Ansible tasks..."

# Files to convert
FILES=(
    "$ROLES_DIR/tasks/cluster.yml"
    "$ROLES_DIR/tasks/preconfigure.yml"
    "$ROLES_DIR/tasks/prepull_images.yml"
    "$ROLES_DIR/tasks/install.yml"
    "$ROLES_DIR/tasks/postconfigure.yml"
    "$ROLES_DIR/tasks/verify.yml"
    "uninstall-smo.yml"
)

# Backup original files
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Processing $file..."
        cp "$file" "$BACKUP_DIR/"
        
        # Replace microk8s kubectl with {{ kubectl_command }}
        sed -i 's/microk8s kubectl/{{ kubectl_command }}/g' "$file"
        
        # Replace microk8s ctr with {{ ctr_command }}
        sed -i 's/microk8s ctr/{{ ctr_command }}/g' "$file"
        
        # Replace microk8s enable commands (comment them out)
        sed -i 's/microk8s enable/# microk8s enable/g' "$file"
        
        # Replace microk8s status commands
        sed -i 's/microk8s status/# microk8s status/g' "$file"
        
        # Replace microk8s config
        sed -i 's/microk8s config/# microk8s config/g' "$file"
        
        # Replace microk8s-hostpath storage class with variable
        sed -i 's/microk8s-hostpath/{{ storage_class | default("standard") }}/g' "$file"
        
        echo "✓ Converted $file"
    else
        echo "⚠ File not found: $file"
    fi
done

echo ""
echo "Conversion complete!"
echo "Backup files saved in: $BACKUP_DIR/"
echo ""
echo "Next steps:"
echo "1. Review the changes with: git diff"
echo "2. Update defaults/main.yml to set:"
echo "   - cluster_type: existing"
echo "   - kubectl_command: kubectl"
echo "   - storage_class: <your-storage-class>"
echo "3. Test the playbook syntax: ansible-playbook deploy-smo.yml --syntax-check"
echo "4. Commit the changes"