job "legacy-proveedores-static" {
  datacenters = ["dc1"]
  type        = "service"

  group "static" {
    count = 1

    volume "legacy-proveedores-static" {
      type      = "host"
      source    = "legacy-proveedores-static"
      read_only = true
    }

    network {
      port "http" {
        static = 8085
      }
    }

    task "nginx" {
      driver = "docker"

      config {
        image        = "nginx:1.25-alpine"
        ports        = ["http"]
        network_mode = "host"

        volumes = [
          "local/nginx.conf:/etc/nginx/conf.d/default.conf"
        ]
      }

      template {
        destination = "local/nginx.conf"
        data        = <<-EOF
        server {
          listen 8085;
          server_name _;

          location /static/ {
            alias /var/www/static/;
            autoindex off;
            expires 1d;
            add_header Cache-Control "public";
          }

          location / {
            return 404;
          }
        }
        EOF
      }

      volume_mount {
        volume      = "legacy-proveedores-static"
        destination = "/var/www/static"
        read_only   = true
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }

  }
}
