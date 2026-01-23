job "gdu-portal-proveedores" {
  datacenters = ["dc1"]
  type        = "service"

  group "app" {
    count = 1

    network {
      port "http" {
        static = 8011
      }
    }

    task "wait-for-postgres" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image        = "busybox:1.36"
        command      = "sh"
        args         = ["-c", "until nc -z 127.0.0.1 5433; do echo 'Esperando PostgreSQL...'; sleep 2; done"]
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
        image        = "ghcr.io/cyberplant/gdu_portal_proveedores:latest"
        command      = "python"
        args         = ["manage.py", "migrate", "--noinput"]
        network_mode = "host"
      }

      template {
        destination = "secrets/app.env"
        env         = true
        data        = <<-EOF
        DJANGO_SETTINGS_MODULE=config.settings.production
        DJANGO_ALLOWED_HOSTS=proveedores.gdu.uy,proveedores.portalgdu.com.uy,localhost
        DATABASE_HOST=127.0.0.1
        DATABASE_PORT=5433
        DATABASE_NAME=gdu_proveedores
        DATABASE_USER=gdu_proveedores
        {{ with nomadVar "nomad/jobs/gdu-portal-proveedores" }}
        DATABASE_PASSWORD={{ .db_password }}
        DJANGO_SECRET_KEY={{ .django_secret_key }}
        {{ else }}
        DATABASE_PASSWORD=CAMBIAR_PASSWORD
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
        image        = "ghcr.io/cyberplant/gdu_portal_proveedores:latest"
        ports        = ["http"]
        network_mode = "host"
      }

      template {
        destination = "secrets/app.env"
        env         = true
        data        = <<-EOF
        DJANGO_SETTINGS_MODULE=config.settings.production
        DJANGO_ALLOWED_HOSTS=proveedores.gdu.uy,proveedores.portalgdu.com.uy,localhost
        DATABASE_HOST=127.0.0.1
        DATABASE_PORT=5433
        DATABASE_NAME=gdu_proveedores
        DATABASE_USER=gdu_proveedores
        {{ with nomadVar "nomad/jobs/gdu-portal-proveedores" }}
        DATABASE_PASSWORD={{ .db_password }}
        DJANGO_SECRET_KEY={{ .django_secret_key }}
        {{ else }}
        DATABASE_PASSWORD=CAMBIAR_PASSWORD
        DJANGO_SECRET_KEY=CAMBIAR_SECRET_KEY
        {{ end }}
        DEBUG=False
        PORT=8011
        EOF
      }

      resources {
        cpu    = 300
        memory = 512
      }

      service {
        name = "gdu-portal-proveedores"
        port = "http"

        check {
          type     = "http"
          path     = "/health/"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}
