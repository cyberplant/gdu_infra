# Despliegue de jobs Nomad
# Requiere que Nomad esté instalado y corriendo
# Los archivos .nomad están en /srv/gdu_infra/salt/states/nomad/jobs/

{% set nomad_jobs_path = "/srv/gdu_infra/salt/states/nomad/jobs" %}

# Verificar que Nomad está corriendo antes de desplegar jobs
check_nomad_running:
  cmd.run:
    - name: /usr/local/bin/nomad status
    - timeout: 10

# Desplegar Traefik primero (reverse proxy)
deploy_traefik:
  cmd.run:
    - name: /usr/local/bin/nomad job run {{ nomad_jobs_path }}/traefik.nomad
    - unless: /usr/local/bin/nomad job status traefik 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: check_nomad_running

# Servir /static/ del legacy proveedores (replica nginx alias /var/www/static)
deploy_legacy_proveedores_static:
  cmd.run:
    - name: /usr/local/bin/nomad job run {{ nomad_jobs_path }}/legacy-proveedores-static.nomad
    - unless: /usr/local/bin/nomad job status legacy-proveedores-static 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_traefik

# Desplegar PostgreSQL
deploy_postgres:
  cmd.run:
    - name: /usr/local/bin/nomad job run {{ nomad_jobs_path }}/postgres.nomad
    - unless: /usr/local/bin/nomad job status postgres 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_traefik

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
    - name: /usr/local/bin/nomad job run {{ nomad_jobs_path }}/postgres-init.nomad
    - require:
      - cmd: wait_postgres

# Desplegar aplicaciones Django
deploy_gdu_usuarios:
  cmd.run:
    - name: /usr/local/bin/nomad job run {{ nomad_jobs_path }}/gdu-usuarios.nomad
    - unless: /usr/local/bin/nomad job status gdu-usuarios 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_postgres_init

deploy_gdu_portal_proveedores:
  cmd.run:
    - name: /usr/local/bin/nomad job run {{ nomad_jobs_path }}/gdu-portal-proveedores.nomad
    - unless: /usr/local/bin/nomad job status gdu-portal-proveedores 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_postgres_init

# Desplegar monitoreo
deploy_monitoring:
  cmd.run:
    - name: /usr/local/bin/nomad job run {{ nomad_jobs_path }}/monitoring.nomad
    - unless: /usr/local/bin/nomad job status monitoring 2>/dev/null | grep -q "Status.*running"
    - require:
      - cmd: deploy_traefik
