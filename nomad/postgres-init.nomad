job "postgres-init" {
  datacenters = ["dc1"]
  type        = "batch"

  group "init" {
    task "create-databases" {
      driver = "docker"

      config {
        image        = "postgres:15-alpine"
        network_mode = "host"
        command      = "sh"
        args         = ["-c", <<-EOF
          until pg_isready -h 127.0.0.1 -p 5433; do
            echo "Esperando a PostgreSQL..."
            sleep 2
          done
          
          echo "Creando bases de datos y usuarios..."
          
          PGPASSWORD=$POSTGRES_PASSWORD psql -h 127.0.0.1 -p 5433 -U postgres <<SQL
          -- Base de datos para gdu_usuarios
          SELECT 'CREATE DATABASE gdu_usuarios' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'gdu_usuarios')\gexec
          SELECT 'CREATE USER gdu_usuarios WITH PASSWORD ''$GDU_USUARIOS_PASSWORD''' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gdu_usuarios')\gexec
          GRANT ALL PRIVILEGES ON DATABASE gdu_usuarios TO gdu_usuarios;
          ALTER DATABASE gdu_usuarios OWNER TO gdu_usuarios;
          
          -- Base de datos para gdu_portal_proveedores
          SELECT 'CREATE DATABASE gdu_portal_proveedores' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'gdu_portal_proveedores')\gexec
          SELECT 'CREATE USER gdu_portal_proveedores WITH PASSWORD ''$GDU_PORTAL_PROVEEDORES_PASSWORD''' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gdu_portal_proveedores')\gexec
          GRANT ALL PRIVILEGES ON DATABASE gdu_portal_proveedores TO gdu_portal_proveedores;
          ALTER DATABASE gdu_portal_proveedores OWNER TO gdu_portal_proveedores;
          
          \l
          \du
          SQL
          
          echo "Inicialización completada."
        EOF
        ]
      }

      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<-EOF
        {{ with nomadVar "nomad/jobs/postgres" }}
        POSTGRES_PASSWORD={{ .postgres_password }}
        GDU_USUARIOS_PASSWORD={{ .gdu_usuarios_password }}
        GDU_PORTAL_PROVEEDORES_PASSWORD={{ .gdu_portal_proveedores_password }}
        {{ else }}
        POSTGRES_PASSWORD=CAMBIAR_PASSWORD_POSTGRES
        GDU_USUARIOS_PASSWORD=CAMBIAR_PASSWORD_USUARIOS
        GDU_PORTAL_PROVEEDORES_PASSWORD=CAMBIAR_PASSWORD_PROVEEDORES
        {{ end }}
        EOF
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
