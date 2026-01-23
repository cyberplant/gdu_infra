job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  group "postgres" {
    count = 1

    network {
      port "db" {
        static = 5433
      }
    }

    volume "postgres-data" {
      type      = "host"
      source    = "postgres-data"
      read_only = false
    }

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:15-alpine"
        ports = ["db"]
      }

      volume_mount {
        volume      = "postgres-data"
        destination = "/var/lib/postgresql/data"
        read_only   = false
      }

      env {
        POSTGRES_USER = "postgres"
      }

      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<-EOF
        {{ with nomadVar "nomad/jobs/postgres" }}
        POSTGRES_PASSWORD={{ .postgres_password }}
        {{ else }}
        POSTGRES_PASSWORD=CAMBIAR_PASSWORD_POSTGRES
        {{ end }}
        EOF
      }

      resources {
        cpu    = 300
        memory = 512
      }

      service {
        name = "postgres"
        port = "db"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
