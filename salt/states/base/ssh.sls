# Configuración SSH segura
{% set ssh_config = pillar.get('ssh', {}) %}

sshd_config:
  file.managed:
    - name: /etc/ssh/sshd_config.d/99-hardening.conf
    - mode: 644
    - contents: |
        # Configuración de seguridad SSH - gestionado por Salt
        Port {{ ssh_config.get('port', 22) }}
        PermitRootLogin {{ ssh_config.get('permit_root_login', 'prohibit-password') }}
        PasswordAuthentication {{ ssh_config.get('password_authentication', 'no') }}
        PubkeyAuthentication {{ ssh_config.get('pubkey_authentication', 'yes') }}
        ChallengeResponseAuthentication no
        UsePAM yes
        X11Forwarding no
        PrintMotd no
        AcceptEnv LANG LC_*
        Subsystem sftp /usr/lib/openssh/sftp-server

sshd_service:
  service.running:
    - name: ssh
    - enable: true
    - watch:
      - file: sshd_config
