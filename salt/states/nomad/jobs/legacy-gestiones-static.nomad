job "legacy-gestiones-static" {
  datacenters = ["dc1"]
  type        = "service"

  group "static" {
    count = 1

    volume "legacy-mrm-static" {
      type      = "host"
      source    = "legacy-mrm-static"
      read_only = true
    }

    volume "legacy-mrm-media" {
      type      = "host"
      source    = "legacy-mrm-media"
      read_only = true
    }

    network {
      port "http" {
        static = 8086
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
          listen 8086;
          server_name _;

          location /static/ {
            alias /var/www/static/mrm/;
            autoindex off;
            expires 1d;
            add_header Cache-Control "public";
          }

          location /media/ {
            alias /var/www/static/mrm-media/;
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
        volume      = "legacy-mrm-static"
        destination = "/var/www/static/mrm"
        read_only   = true
      }

      volume_mount {
        volume      = "legacy-mrm-media"
        destination = "/var/www/static/mrm-media"
        read_only   = true
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }

  }
}
