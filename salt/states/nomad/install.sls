# Instalación de Nomad
{% set nomad_version = pillar.get('nomad', {}).get('version', '1.7.3') %}

nomad_dependencies:
  pkg.installed:
    - pkgs:
      - unzip
      - curl

nomad_download:
  file.managed:
    - name: /tmp/nomad.zip
    - source: https://releases.hashicorp.com/nomad/{{ nomad_version }}/nomad_{{ nomad_version }}_linux_amd64.zip
    - skip_verify: true
    - unless: test -f /usr/local/bin/nomad

nomad_extract:
  cmd.run:
    - name: unzip -o /tmp/nomad.zip -d /usr/local/bin/
    - unless: test -f /usr/local/bin/nomad
    - require:
      - file: nomad_download

nomad_permissions:
  file.managed:
    - name: /usr/local/bin/nomad
    - mode: 755
    - require:
      - cmd: nomad_extract

nomad_config_dir:
  file.directory:
    - name: /etc/nomad.d
    - mode: 755

nomad_data_dir:
  file.directory:
    - name: /var/lib/nomad
    - mode: 755

# Directorios para volúmenes
{% for dir in ['traefik-certs', 'postgres-usuarios', 'postgres-proveedores', 'usuarios-media', 'proveedores-media', 'prometheus', 'grafana', 'usuarios-oidc'] %}
gdu_volume_{{ dir }}:
  file.directory:
    - name: /var/lib/gdu/{{ dir }}
    - mode: 755
    - makedirs: true
{% endfor %}

nomad_server_config:
  file.managed:
    - name: /etc/nomad.d/server.hcl
    - source: salt://nomad/files/server.hcl
    - mode: 644
    - require:
      - file: nomad_config_dir

nomad_systemd:
  file.managed:
    - name: /etc/systemd/system/nomad.service
    - contents: |
        [Unit]
        Description=Nomad
        Documentation=https://www.nomadproject.io/docs
        Wants=network-online.target
        After=network-online.target

        [Service]
        ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d
        ExecReload=/bin/kill -HUP $MAINPID
        KillMode=process
        KillSignal=SIGINT
        LimitNOFILE=65536
        LimitNPROC=infinity
        Restart=on-failure
        RestartSec=2
        TasksMax=infinity
        OOMScoreAdjust=-1000

        [Install]
        WantedBy=multi-user.target
    - mode: 644

nomad_service:
  service.running:
    - name: nomad
    - enable: true
    - require:
      - file: nomad_systemd
      - file: nomad_server_config
      - file: nomad_permissions
    - watch:
      - file: nomad_server_config

nomad_wait_ready:
  cmd.run:
    - name: |
        for i in $(seq 1 30); do
          if curl -sf http://127.0.0.1:4646/v1/status/leader > /dev/null 2>&1; then
            exit 0
          fi
          sleep 2
        done
        exit 1
    - timeout: 120
    - require:
      - service: nomad_service
