# Despliegue de jobs Nomad
# Requiere que Nomad esté instalado y corriendo

# Verificar que Nomad está corriendo antes de desplegar jobs
check_nomad_running:
  cmd.run:
    - name: /usr/local/bin/nomad status
    - timeout: 10

nomad_jobs_dir:
  file.directory:
    - name: /srv/gdu_infra/nomad
    - makedirs: true

# Copiar archivos de jobs
{% for job in ['traefik', 'postgres', 'postgres-init', 'gdu-usuarios', 'gdu-portal-proveedores', 'monitoring'] %}
nomad_job_{{ job }}:
  file.managed:
    - name: /srv/gdu_infra/nomad/{{ job }}.nomad
    - source: salt://nomad/jobs/{{ job }}.nomad
    - makedirs: true
{% endfor %}

# Desplegar Traefik primero (reverse proxy)
deploy_traefik:
  cmd.run:
    - name: /usr/local/bin/nomad job run /srv/gdu_infra/nomad/traefik.nomad
    - unless: /usr/local/bin/nomad job status traefik 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: check_nomad_running
      - file: nomad_job_traefik

# Desplegar PostgreSQL
deploy_postgres:
  cmd.run:
    - name: /usr/local/bin/nomad job run /srv/gdu_infra/nomad/postgres.nomad
    - unless: /usr/local/bin/nomad job status postgres 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_traefik
      - file: nomad_job_postgres

# Esperar a que PostgreSQL esté listo
wait_postgres:
  cmd.run:
    - name: |
        for i in $(seq 1 30); do
          if nc -z 127.0.0.1 5433 2>/dev/null; then
            exit 0
          fi
          sleep 2
        done
        exit 1
    - timeout: 120
    - require:
      - cmd: deploy_postgres

# Inicializar bases de datos
deploy_postgres_init:
  cmd.run:
    - name: /usr/local/bin/nomad job run /srv/gdu_infra/nomad/postgres-init.nomad
    - require:
      - cmd: wait_postgres
      - file: nomad_job_postgres-init

# Desplegar aplicaciones Django
deploy_gdu_usuarios:
  cmd.run:
    - name: /usr/local/bin/nomad job run /srv/gdu_infra/nomad/gdu-usuarios.nomad
    - unless: /usr/local/bin/nomad job status gdu-usuarios 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_postgres_init
      - file: nomad_job_gdu-usuarios

deploy_gdu_portal_proveedores:
  cmd.run:
    - name: /usr/local/bin/nomad job run /srv/gdu_infra/nomad/gdu-portal-proveedores.nomad
    - unless: /usr/local/bin/nomad job status gdu-portal-proveedores 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_postgres_init
      - file: nomad_job_gdu-portal-proveedores

# Desplegar monitoreo
deploy_monitoring:
  cmd.run:
    - name: /usr/local/bin/nomad job run /srv/gdu_infra/nomad/monitoring.nomad
    - unless: /usr/local/bin/nomad job status monitoring 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_traefik
      - file: nomad_job_monitoring
