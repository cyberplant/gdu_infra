# GDU Infra

Infraestructura para el Grupo Disco del Uruguay - Gestión de servidores y deployment de aplicaciones.

## Arquitectura

- **Orquestación**: Nomad (HashiCorp)
- **Gestión de configuración**: Salt masterless
- **Reverse Proxy**: Traefik v3
- **Certificados SSL**: Let's Encrypt (via Traefik)
- **Registry**: ghcr.io (GitHub Container Registry)

## Dominios

| Dominio | Aplicación |
|---------|------------|
| usuarios.portalgdu.com.uy | gdu_usuarios |
| auth.portalgdu.com.uy | gdu_usuarios (OAuth /o) |
| proveedores.gdu.uy | gdu_portal_proveedores |
| proveedores.portalgdu.com.uy | gdu_portal_proveedores |
| grafana.portalgdu.com.uy | Grafana (monitoreo) |

## Estructura

```
gdu_infra/
├── salt/
│   ├── pillar/           # Variables y configuración
│   ├── states/
│   │   ├── base/         # usuarios, SSH, firewall
│   │   └── nomad/        # Instalación Nomad
│   └── minion.conf       # Config para masterless
├── nomad/
│   ├── server.hcl        # Configuración servidor Nomad
│   ├── traefik.nomad     # Reverse proxy + SSL
│   ├── gdu-usuarios.nomad
│   ├── gdu-portal-proveedores.nomad
│   └── monitoring.nomad  # Prometheus + Grafana
├── scripts/
│   └── bootstrap.sh      # Script inicial para el servidor
└── README.md
```

## Aplicaciones

### gdu_usuarios
- **Dominio**: usuarios.portalgdu.com.uy
- **Imagen**: `ghcr.io/cyberplant/gdu_usuarios:latest`
- **Stack**: Django + PostgreSQL

### gdu_portal_proveedores
- **Dominios**: proveedores.gdu.uy, proveedores.portalgdu.com.uy
- **Imagen**: `ghcr.io/cyberplant/gdu_portal_proveedores:latest`
- **Stack**: Django + PostgreSQL

## Uso

### Bootstrap inicial del servidor

```bash
# En un servidor nuevo con Debian/Ubuntu
curl -fsSL https://raw.githubusercontent.com/cyberplant/gdu_infra/main/scripts/bootstrap.sh | sudo bash
```

### Aplicar configuración Salt

```bash
# Clonar el repo (si no está)
git clone git@github.com:cyberplant/gdu_infra.git /srv/gdu_infra

# Aplicar todos los estados
sudo salt-call --local state.apply

# Aplicar estado específico
sudo salt-call --local state.apply k3s
```

### Comandos K3s útiles

```bash
# Ver estado del cluster
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A

# Aplicar manifiestos
sudo k3s kubectl apply -f /srv/gdu_infra/k8s/gdu-usuarios/

# Ver logs de un pod
sudo k3s kubectl logs -f deployment/gdu-usuarios -n gdu
```

## Monitoreo

- **Prometheus**: Métricas del cluster y aplicaciones
- **Grafana**: Dashboards (puerto 3000)
- **Alertas**: Notificaciones por email/Slack cuando algo falle

## Requisitos del servidor

- Debian 12 / Ubuntu 22.04+
- Mínimo 2 CPU, 4GB RAM, 40GB disco
- Acceso root
- Conexión a internet
