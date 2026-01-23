job "traefik" {
  datacenters = ["dc1"]
  type        = "service"

  group "traefik" {
    count = 1

    network {
      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "admin" {
        static = 8080
      }
    }

    service {
      name = "traefik"
      port = "http"

      check {
        type     = "http"
        path     = "/ping"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = "traefik:v3.0"
        network_mode = "host"

        volumes = [
          "local/traefik.yml:/etc/traefik/traefik.yml",
          "local/dynamic:/etc/traefik/dynamic",
          "/var/run/docker.sock:/var/run/docker.sock:ro",
          "traefik-certs:/letsencrypt"
        ]
      }

      template {
        destination = "local/traefik.yml"
        data        = <<-EOF
        api:
          dashboard: true
          insecure: true

        ping:
          entryPoint: http

        entryPoints:
          http:
            address: ":80"
            http:
              redirections:
                entryPoint:
                  to: https
                  scheme: https
          https:
            address: ":443"
            http:
              tls:
                certResolver: letsencrypt

        certificatesResolvers:
          letsencrypt:
            acme:
              email: luar@roar.uy
              storage: /letsencrypt/acme.json
              httpChallenge:
                entryPoint: http

        providers:
          file:
            directory: /etc/traefik/dynamic
            watch: true
        EOF
      }

      template {
        destination = "local/dynamic/routes.yml"
        data        = <<-EOF
        http:
          routers:
            # ============================================
            # SISTEMAS NUEVOS (Nomad)
            # ============================================
            gdu-usuarios:
              rule: "Host(`usuarios.portalgdu.com.uy`)"
              service: gdu-usuarios
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            gdu-auth:
              rule: "Host(`auth.portalgdu.com.uy`)"
              service: gdu-usuarios
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            gdu-proveedores-new:
              rule: "Host(`proveedores.portalgdu.com.uy`)"
              service: gdu-portal-proveedores
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            grafana:
              rule: "Host(`grafana.portalgdu.com.uy`)"
              service: grafana
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            # ============================================
            # SISTEMAS LEGACY (Docker existente)
            # ============================================
            legacy-proveedores:
              rule: "Host(`proveedores.gdu.uy`) || Host(`www.proveedores.gdu.uy`)"
              service: legacy-portal-gdu
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            legacy-gestiones:
              rule: "Host(`gestiones.portalgdu.com.uy`) || Host(`gduprod.roar.uy`)"
              service: legacy-meeting-room
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

          services:
            # Nuevos servicios (Nomad)
            gdu-usuarios:
              loadBalancer:
                servers:
                  - url: "http://127.0.0.1:8010"

            gdu-portal-proveedores:
              loadBalancer:
                servers:
                  - url: "http://127.0.0.1:8011"

            grafana:
              loadBalancer:
                servers:
                  - url: "http://127.0.0.1:3000"

            # Legacy services (Docker existente)
            legacy-portal-gdu:
              loadBalancer:
                servers:
                  - url: "http://127.0.0.1:8000"

            legacy-meeting-room:
              loadBalancer:
                servers:
                  - url: "http://127.0.0.1:8001"
        EOF
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    volume "traefik-certs" {
      type      = "host"
      source    = "traefik-certs"
      read_only = false
    }
  }
}
