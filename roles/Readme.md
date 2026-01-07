# Basic installation
ansible-playbook -i inventory.ini setup-k8s.yml

# With specific tags
ansible-playbook -i inventory.ini setup-k8s.yml --tags "docker,kubernetes"

# Skip specific components
ansible-playbook -i inventory.ini setup-k8s.yml --skip-tags "helm"

# With extra variables
ansible-playbook -i inventory.ini setup-k8s.yml -e "k8s_version=1.28.0 helm_version=3.12.0"
