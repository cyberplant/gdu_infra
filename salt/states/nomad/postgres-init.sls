# Inicialización de bases de datos PostgreSQL para Nomad
# Requiere que PostgreSQL esté corriendo en el puerto 5433

{% set secrets_file = '/root/.gdu_secrets' %}

# Esperar a que PostgreSQL esté disponible
wait_for_postgres:
  cmd.run:
    - name: |
        for i in $(seq 1 30); do
          if nc -z 127.0.0.1 5433 2>/dev/null; then
            exit 0
          fi
          echo "Esperando PostgreSQL... ($i)"
          sleep 2
        done
        exit 1
    - timeout: 120

# Obtener el container ID de PostgreSQL
{% set pg_container_cmd = "docker ps -q --filter ancestor=postgres:15-alpine | head -1" %}

# Crear usuario y base de datos para gdu_usuarios
create_gdu_usuarios_user:
  cmd.run:
    - name: |
        source {{ secrets_file }}
        PG_CONTAINER=$({{ pg_container_cmd }})
        docker exec $PG_CONTAINER psql -U postgres -p 5433 -c "CREATE USER gdu_usuarios WITH PASSWORD '$GDU_USUARIOS_DB_PASS';" 2>/dev/null || true
    - require:
      - cmd: wait_for_postgres
    - unless: |
        PG_CONTAINER=$({{ pg_container_cmd }})
        docker exec $PG_CONTAINER psql -U postgres -p 5433 -tAc "SELECT 1 FROM pg_roles WHERE rolname='gdu_usuarios'" | grep -q 1

create_gdu_usuarios_db:
  cmd.run:
    - name: |
        PG_CONTAINER=$({{ pg_container_cmd }})
        docker exec $PG_CONTAINER psql -U postgres -p 5433 -c "CREATE DATABASE gdu_usuarios OWNER gdu_usuarios;"
    - require:
      - cmd: create_gdu_usuarios_user
    - unless: |
        PG_CONTAINER=$({{ pg_container_cmd }})
        docker exec $PG_CONTAINER psql -U postgres -p 5433 -tAc "SELECT 1 FROM pg_database WHERE datname='gdu_usuarios'" | grep -q 1

# Crear usuario y base de datos para gdu_portal_proveedores
create_gdu_portal_proveedores_user:
  cmd.run:
    - name: |
        source {{ secrets_file }}
        PG_CONTAINER=$({{ pg_container_cmd }})
        docker exec $PG_CONTAINER psql -U postgres -p 5433 -c "CREATE USER gdu_portal_proveedores WITH PASSWORD '$GDU_PORTAL_PROVEEDORES_DB_PASS';" 2>/dev/null || true
    - require:
      - cmd: wait_for_postgres
    - unless: |
        PG_CONTAINER=$({{ pg_container_cmd }})
        docker exec $PG_CONTAINER psql -U postgres -p 5433 -tAc "SELECT 1 FROM pg_roles WHERE rolname='gdu_portal_proveedores'" | grep -q 1

create_gdu_portal_proveedores_db:
  cmd.run:
    - name: |
        PG_CONTAINER=$({{ pg_container_cmd }})
        docker exec $PG_CONTAINER psql -U postgres -p 5433 -c "CREATE DATABASE gdu_portal_proveedores OWNER gdu_portal_proveedores;"
    - require:
      - cmd: create_gdu_portal_proveedores_user
    - unless: |
        PG_CONTAINER=$({{ pg_container_cmd }})
        docker exec $PG_CONTAINER psql -U postgres -p 5433 -tAc "SELECT 1 FROM pg_database WHERE datname='gdu_portal_proveedores'" | grep -q 1
