job "gdu-usuarios" {
  datacenters = ["dc1"]
  type        = "service"

  group "app" {
    count = 1

    network {
      port "http" {
        static = 8010
      }
    }

    task "wait-for-postgres" {
      driver = "docker"
      
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "busybox:1.36"
        command = "sh"
        args    = ["-c", "i=0; while ! nc -z 127.0.0.1 5433 2>/dev/null; do echo \"Esperando PostgreSQL... ($i s)\"; i=$((i+2)); sleep 2; done; echo \"PostgreSQL disponible!\""]

        network_mode = "host"
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }

    task "migrate" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "ghcr.io/cyberplant/gdu_usuarios:latest"
        command = "python"
        args    = ["manage.py", "migrate", "--noinput"]
        network_mode = "host"
      }

      template {
        destination = "secrets/app.env"
        env         = true
        data        = <<-EOF
        DJANGO_SETTINGS_MODULE=gdu_usuarios.settings
        DJANGO_ALLOWED_HOSTS=usuarios.portalgdu.com.uy,auth.portalgdu.com.uy,auth.proveedores.gdu.uy,localhost
        DB_ENGINE=django.db.backends.postgresql
        DB_HOST=127.0.0.1
        DB_PORT=5433
        DB_NAME=gdu_usuarios
        DB_USER=gdu_usuarios
        {{ with nomadVar "nomad/jobs/gdu-usuarios" }}
        DB_PASSWORD={{ .db_password }}
        DJANGO_SECRET_KEY={{ .django_secret_key }}
        {{ else }}
        DB_PASSWORD=CAMBIAR_PASSWORD
        DJANGO_SECRET_KEY=CAMBIAR_SECRET_KEY
        {{ end }}
        DEBUG=False
        EOF
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    task "django" {
      driver = "docker"

      config {
        image        = "ghcr.io/cyberplant/gdu_usuarios:latest"
        ports        = ["http"]
        network_mode = "host"

        # Si la imagen usa gunicorn
        # command = "gunicorn"
        # args    = ["config.wsgi:application", "--bind", "0.0.0.0:8001"]
      }

      template {
        destination = "secrets/app.env"
        env         = true
        data        = <<-EOF
        DJANGO_SETTINGS_MODULE=gdu_usuarios.settings
        DJANGO_ALLOWED_HOSTS=usuarios.portalgdu.com.uy,auth.portalgdu.com.uy,auth.proveedores.gdu.uy,localhost
        DB_ENGINE=django.db.backends.postgresql
        DB_HOST=127.0.0.1
        DB_PORT=5433
        DB_NAME=gdu_usuarios
        DB_USER=gdu_usuarios
        {{ with nomadVar "nomad/jobs/gdu-usuarios" }}
        DB_PASSWORD={{ .db_password }}
        DJANGO_SECRET_KEY={{ .django_secret_key }}
        {{ else }}
        DB_PASSWORD=CAMBIAR_PASSWORD
        DJANGO_SECRET_KEY=CAMBIAR_SECRET_KEY
        {{ end }}
        DEBUG=False
        PORT=8010
        EOF
      }

      resources {
        cpu    = 300
        memory = 512
      }

      # No usamos service discovery (requiere Consul)
    }

  }
}
