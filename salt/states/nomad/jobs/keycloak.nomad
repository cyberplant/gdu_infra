job "keycloak-test" {
  datacenters = ["dc1"]
  type        = "service"

  group "keycloak" {
    count = 1

    network {
      port "http" {
        static = 8180
      }
    }

    volume "keycloak-data" {
      type      = "host"
      source    = "keycloak-data"
      read_only = false
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

    task "keycloak" {
      driver = "docker"

      config {
        image        = "quay.io/keycloak/keycloak:24.0"
        network_mode = "host"
        
        command = "start-dev"
        args = [
          "--http-port=8180",
          "--hostname-strict=false",
          "--proxy=edge",
          "--http-relative-path=/",
        ]
      }

      env {
        # Admin credentials
        KEYCLOAK_ADMIN          = "admin"
        KEYCLOAK_ADMIN_PASSWORD = "admin"
        
        # Database config (usa el mismo Postgres que gdu-usuarios)
        KC_DB              = "postgres"
        KC_DB_URL          = "jdbc:postgresql://127.0.0.1:5433/keycloak"
        KC_DB_USERNAME     = "postgres"
        KC_DB_PASSWORD     = "${POSTGRES_PASSWORD}"
        
        # Proxy settings para Traefik
        KC_PROXY           = "edge"
        KC_HOSTNAME_STRICT = "false"
        KC_HTTP_ENABLED    = "true"
        
        # Hostname
        KC_HOSTNAME        = "keycloak.roar.uy"
      }

      volume_mount {
        volume      = "keycloak-data"
        destination = "/var/lib/gdu/keycloak"
        read_only   = false
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}
