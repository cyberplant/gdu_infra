# Configuración SSH segura
{% set ssh_config = pillar.get('ssh', {}) %}

sshd_config:
  file.managed:
    - name: /etc/ssh/sshd_config.d/99-hardening.conf
    - mode: 644
    - contents: |
        # Configuración de seguridad SSH - gestionado por Salt
        Port 999
        Port 7822
        PermitRootLogin prohibit-password
        PasswordAuthentication no
        PubkeyAuthentication yes
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
    # No reiniciar automáticamente para evitar perder conexión
    # Reiniciar manualmente: systemctl reload ssh
