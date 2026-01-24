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

    # No usamos service discovery (requiere Consul)
    # Los health checks se hacen via Traefik ping endpoint

    task "traefik" {
      driver = "docker"

      config {
        image        = "traefik:v3.0"
        network_mode = "host"

        volumes = [
          "local/traefik.yml:/etc/traefik/traefik.yml",
          "local/dynamic:/etc/traefik/dynamic",
          "/var/run/docker.sock:/var/run/docker.sock:ro"
        ]
      }

      template {
        destination = "local/traefik.yml"
        data        = <<-EOF
        api:
          dashboard: true
          insecure: true

        accessLog:
          format: common
          filters:
            statusCodes:
              - "400-599"

        log:
          level: DEBUG

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
            # SISTEMAS LEGACY (Docker existente) - ACTIVOS
            # ============================================
            legacy-proveedores:
              rule: "Host(`proveedores.gdu.uy`)"
              service: legacy-portal-gdu
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            legacy-gestiones:
              rule: "Host(`gestiones.portalgdu.com.uy`)"
              service: legacy-meeting-room
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            # ============================================
            # SISTEMAS NUEVOS (Nomad) - ACTIVOS
            # ============================================

            # gdu-usuarios completo
            gdu-usuarios:
              rule: "Host(`usuarios.portalgdu.com.uy`)"
              service: gdu-usuarios
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            # auth.portalgdu.com.uy/ -> redirect a login
            gdu-auth-root:
              rule: "Host(`auth.portalgdu.com.uy`) && Path(`/`)"
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt
              middlewares:
                - redirect-to-login
              service: gdu-usuarios

            # auth.portalgdu.com.uy/* -> gdu-usuarios/o/*
            gdu-auth-portal:
              rule: "Host(`auth.portalgdu.com.uy`) && !Path(`/`)"
              service: gdu-usuarios
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt
              middlewares:
                - add-oauth-prefix

            # gdu-portal-proveedores
            gdu-proveedores-new:
              rule: "Host(`proveedores.portalgdu.com.uy`)"
              service: gdu-portal-proveedores
              entryPoints:
                - https
              tls:
                certResolver: letsencrypt

            # ============================================
            # SISTEMAS NUEVOS (Nomad) - PENDIENTES
            # ============================================
            # grafana:
            #   rule: "Host(`grafana.portalgdu.com.uy`)"
            #   service: grafana
            #   entryPoints:
            #     - https
            #   tls:
            #     certResolver: letsencrypt

          middlewares:
            add-oauth-prefix:
              addPrefix:
                prefix: "/o"
            redirect-to-login:
              redirectRegex:
                regex: "^https://auth.portalgdu.com.uy/$"
                replacement: "https://usuarios.portalgdu.com.uy/accounts/login/"
                permanent: false

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

      volume_mount {
        volume      = "traefik-certs"
        destination = "/letsencrypt"
        read_only   = false
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
