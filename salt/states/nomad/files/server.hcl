# Configuración del servidor Nomad
# Gestionado por Salt

datacenter = "dc1"
data_dir   = "/var/lib/nomad"

server {
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true
  
  # Para OpenVZ: especificar interfaz de red manualmente
  # Si no funciona con venet0, cambiar a eth0 o la interfaz correcta
  network_interface = "venet0"

  host_volume "traefik-certs" {
    path      = "/var/lib/gdu/traefik-certs"
    read_only = false
  }

  host_volume "postgres-data" {
    path      = "/var/lib/gdu/postgres-nomad"
    read_only = false
  }

  host_volume "gdu-usuarios-media" {
    path      = "/var/lib/gdu/usuarios-media"
    read_only = false
  }

  host_volume "gdu-proveedores-media" {
    path      = "/var/lib/gdu/proveedores-media"
    read_only = false
  }

  host_volume "legacy-proveedores-static" {
    path      = "/var/www/static"
    read_only = true
  }

  host_volume "legacy-mrm-static" {
    path      = "/var/www/static/mrm"
    read_only = true
  }

  host_volume "legacy-mrm-media" {
    path      = "/var/www/static/mrm-media"
    read_only = true
  }

  host_volume "prometheus-data" {
    path      = "/var/lib/gdu/prometheus"
    read_only = false
  }

  host_volume "grafana-data" {
    path      = "/var/lib/gdu/grafana"
    read_only = false
  }

  host_volume "gdu-usuarios-oidc" {
    path      = "/var/lib/gdu/usuarios-oidc"
    read_only = false
  }
}

plugin "docker" {
  config {
    allow_privileged = false
    
    volumes {
      enabled = true
    }

    auth {
      config = "/root/.docker/config.json"
    }
  }
}

telemetry {
  prometheus_metrics         = true
  disable_hostname           = true
  publish_allocation_metrics = true
  publish_node_metrics       = true
}
