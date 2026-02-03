# Ansible Configuration for Payment Form Infrastructure

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   ├── dev                  # Local development inventory
│   └── sandbox              # Sandbox environment inventory
├── playbooks/
│   ├── deploy-backend.yml   # Backend deployment
│   └── deploy-traefik.yml   # Traefik reverse proxy
├── roles/
│   └── traefik/            # Traefik role
│       ├── tasks/
│       ├── templates/
│       ├── handlers/
│       └── files/
├── templates/
│   └── backend.env.j2       # Backend environment template
└── vars/
    ├── common.yml           # Common variables
    ├── dev.yml              # Dev environment
    ├── sandbox.yml          # Sandbox environment
    └── backend.yml          # Backend service vars
```

## Prerequisites

```bash
# Install Ansible
pip3 install ansible

# Install required collections
ansible-galaxy collection install community.docker
```

## Usage

### Local Development

```bash
cd ansible
ansible-playbook -i inventory/dev playbooks/deploy-backend.yml
```

### Sandbox Deployment

```bash
# 1. Update inventory with EC2 IP
EC2_IP=$(cd .. && tofu output -raw ec2_public_ip)
sed -i "s/# backend-1.*/backend-1 ansible_host=${EC2_IP}/" inventory/sandbox

# 2. Test connection
ansible -i inventory/sandbox backend -m ping

# 3. Deploy
ansible-playbook -i inventory/sandbox playbooks/deploy-backend.yml
```

## Notes

- Ubuntu 22.04 LTS only
- Docker installed automatically
- Client & Renderer use AWS Amplify (not Ansible)
- Terraform outputs should be exported as env vars before running playbooks
