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
        DJANGO_SETTINGS_MODULE=portal_proveedores.settings
        DJANGO_ALLOWED_HOSTS=proveedores.gdu.uy,proveedores.portalgdu.com.uy,localhost
        DB_ENGINE=django.db.backends.postgresql
        DB_HOST=127.0.0.1
        DB_PORT=5433
        DB_NAME=gdu_portal_proveedores
        DB_USER=gdu_portal_proveedores
        {{ with nomadVar "nomad/jobs/gdu-portal-proveedores" }}
        DB_PASSWORD={{ .db_password }}
        DJANGO_SECRET_KEY={{ .django_secret_key }}
        {{ else }}
        DB_PASSWORD=CAMBIAR_PASSWORD
        DJANGO_SECRET_KEY=CAMBIAR_SECRET_KEY
        {{ end }}
        DEBUG=False
        OAUTH2_IDP_URL=https://auth.portalgdu.com.uy
        SOCIAL_AUTH_GDU_USUARIOS_REDIRECT_URI=https://proveedores.portalgdu.com.uy/oauth/complete/gdu-usuarios/
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
        DJANGO_SETTINGS_MODULE=portal_proveedores.settings
        DJANGO_ALLOWED_HOSTS=proveedores.gdu.uy,proveedores.portalgdu.com.uy,localhost
        DATABASE_HOST=127.0.0.1
        DATABASE_PORT=5433
        DATABASE_NAME=gdu_portal_proveedores
        DATABASE_USER=gdu_portal_proveedores
        {{ with nomadVar "nomad/jobs/gdu-portal-proveedores" }}
        DATABASE_PASSWORD={{ .db_password }}
        DJANGO_SECRET_KEY={{ .django_secret_key }}
        {{ end }}
        DEBUG=False
        PORT=8011
        OAUTH2_IDP_URL=https://auth.portalgdu.com.uy
        SOCIAL_AUTH_GDU_USUARIOS_REDIRECT_URI=https://proveedores.portalgdu.com.uy/oauth/complete/gdu-usuarios/
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
