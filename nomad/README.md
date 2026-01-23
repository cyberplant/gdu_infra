# Nomad Jobs - GDU Infra

Configuración de Nomad para el Grupo Disco del Uruguay.

## Arquitectura

```
                    Internet
                        │
                        ▼
┌──────────────────────────────────────────────────┐
│              Traefik (80, 443)                   │
│         SSL automático con Let's Encrypt         │
└──────────────────────────────────────────────────┘
        │              │              │
        ▼              ▼              ▼
   gdu-usuarios   gdu-proveedores   grafana
    (8001)           (8002)         (3000)
        │              │
        ▼              ▼
   postgres:5432   postgres:5433
```

## Jobs

| Job | Puerto | Descripción |
|-----|--------|-------------|
| traefik | 80, 443, 8080 | Reverse proxy + SSL |
| postgres | 5432 | PostgreSQL compartido |
| postgres-init | - | Inicializa DBs (batch) |
| gdu-usuarios | 8001 | App Django usuarios |
| gdu-portal-proveedores | 8002 | Portal proveedores |
| monitoring | 9090, 3000 | Prometheus + Grafana |

## Dominios

| Dominio | Servicio |
|---------|----------|
| usuarios.portalgdu.com.uy | gdu-usuarios |
| auth.portalgdu.com.uy | gdu-usuarios |
| proveedores.gdu.uy | gdu-portal-proveedores |
| proveedores.portalgdu.com.uy | gdu-portal-proveedores |
| grafana.portalgdu.com.uy | grafana |

## Instalación

### 1. Instalar Nomad

```bash
# Descargar e instalar
curl -fsSL https://releases.hashicorp.com/nomad/1.7.3/nomad_1.7.3_linux_amd64.zip -o nomad.zip
unzip nomad.zip
mv nomad /usr/local/bin/
chmod +x /usr/local/bin/nomad

# Crear directorios
mkdir -p /etc/nomad.d
mkdir -p /var/lib/nomad
mkdir -p /var/lib/gdu/{traefik-certs,postgres-usuarios,postgres-proveedores,usuarios-media,proveedores-media,prometheus,grafana}

# Copiar configuración
cp server.hcl /etc/nomad.d/

# Crear servicio systemd
cat > /etc/systemd/system/nomad.service << 'EOF'
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/docs
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGINT
LimitNOFILE=65536
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
TasksMax=infinity
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nomad
systemctl start nomad
```

### 2. Configurar secrets con Nomad Variables

```bash
# PostgreSQL (usuario root y passwords de apps)
nomad var put nomad/jobs/postgres \
  postgres_password="PASSWORD_ROOT" \
  gdu_usuarios_password="PASSWORD_USUARIOS" \
  gdu_proveedores_password="PASSWORD_PROVEEDORES"

# gdu-usuarios
nomad var put nomad/jobs/gdu-usuarios \
  db_password="PASSWORD_USUARIOS" \
  django_secret_key="TU_SECRET_KEY_50_CHARS"

# gdu-portal-proveedores
nomad var put nomad/jobs/gdu-portal-proveedores \
  db_password="PASSWORD_PROVEEDORES" \
  django_secret_key="TU_SECRET_KEY_50_CHARS"

# Grafana
nomad var put nomad/jobs/monitoring \
  grafana_admin_password="PASSWORD_GRAFANA"
```

### 3. Login a GitHub Container Registry

```bash
echo "TU_GITHUB_TOKEN" | docker login ghcr.io -u cyberplant --password-stdin
```

### 4. Desplegar jobs

```bash
# En orden:
nomad job run traefik.nomad
nomad job run postgres.nomad
nomad job run postgres-init.nomad  # Solo la primera vez
nomad job run gdu-usuarios.nomad
nomad job run gdu-portal-proveedores.nomad
nomad job run monitoring.nomad
```

## Comandos útiles

```bash
# Ver estado de jobs
nomad job status

# Ver logs de un job
nomad alloc logs -f <alloc-id>

# Reiniciar un job
nomad job restart <job-name>

# Escalar un job
nomad job scale <job-name> <count>

# UI web (si está habilitada)
# http://servidor:4646
```

## Estructura de archivos

```
nomad/
├── server.hcl              # Configuración del servidor Nomad
├── traefik.nomad           # Reverse proxy + SSL
├── postgres.nomad          # PostgreSQL compartido
├── postgres-init.nomad     # Inicialización de DBs
├── gdu-usuarios.nomad      # App Django usuarios
├── gdu-portal-proveedores.nomad  # Portal proveedores
├── monitoring.nomad        # Prometheus + Grafana
└── README.md
```
