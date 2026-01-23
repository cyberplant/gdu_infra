job "monitoring" {
  datacenters = ["dc1"]
  type        = "service"

  group "prometheus" {
    count = 1

    network {
      port "prometheus" {
        static = 9090
      }
    }

    task "prometheus" {
      driver = "docker"

      config {
        image = "prom/prometheus:v2.48.0"
        ports = ["prometheus"]

        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--storage.tsdb.retention.time=30d",
          "--web.enable-lifecycle"
        ]

        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml",
          "/var/lib/gdu/prometheus:/prometheus"
        ]
      }

      template {
        destination = "local/prometheus.yml"
        data        = <<-EOF
        global:
          scrape_interval: 15s
          evaluation_interval: 15s

        scrape_configs:
          - job_name: 'prometheus'
            static_configs:
              - targets: ['localhost:9090']

          - job_name: 'nomad'
            metrics_path: /v1/metrics
            params:
              format: ['prometheus']
            static_configs:
              - targets: ['127.0.0.1:4646']

          - job_name: 'traefik'
            static_configs:
              - targets: ['127.0.0.1:8080']

          - job_name: 'gdu-usuarios'
            static_configs:
              - targets: ['127.0.0.1:8001']
            metrics_path: /metrics

          - job_name: 'gdu-proveedores'
            static_configs:
              - targets: ['127.0.0.1:8002']
            metrics_path: /metrics
        EOF
      }

      resources {
        cpu    = 200
        memory = 512
      }

      service {
        name = "prometheus"
        port = "prometheus"

        check {
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }

  group "grafana" {
    count = 1

    network {
      port "grafana" {
        static = 3000
      }
    }

    task "grafana" {
      driver = "docker"

      config {
        image = "grafana/grafana:10.2.2"
        ports = ["grafana"]

        volumes = [
          "local/datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml",
          "/var/lib/gdu/grafana:/var/lib/grafana"
        ]
      }

      template {
        destination = "local/datasources.yml"
        data        = <<-EOF
        apiVersion: 1
        datasources:
          - name: Prometheus
            type: prometheus
            url: http://127.0.0.1:9090
            access: proxy
            isDefault: true
        EOF
      }

      env {
        GF_SERVER_ROOT_URL = "https://grafana.portalgdu.com.uy"
        GF_SECURITY_ADMIN_USER = "admin"
      }

      template {
        destination = "secrets/grafana.env"
        env         = true
        data        = <<-EOF
        GF_SECURITY_ADMIN_PASSWORD={{ key "gdu/grafana-admin-password" | default "CAMBIAR_PASSWORD" }}
        EOF
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "grafana"
        port = "grafana"

        check {
          type     = "http"
          path     = "/api/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
