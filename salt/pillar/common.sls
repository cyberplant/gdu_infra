# Configuración común
timezone: America/Montevideo

# Paquetes base a instalar
base_packages:
  - vim
  - htop
  - curl
  - wget
  - git
  - jq
  - net-tools
  - unzip

# Firewall
firewall:
  enabled: true
  allowed_ports:
    - 22/tcp      # SSH
    - 80/tcp      # HTTP
    - 443/tcp     # HTTPS
    - 6443/tcp    # K3s API server
    - 10250/tcp   # Kubelet metrics

# SSH
ssh:
  port: 22
  permit_root_login: 'prohibit-password'
  password_authentication: 'no'
  pubkey_authentication: 'yes'
