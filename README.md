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
│   │   └── nomad/        # Jobs y configuración Nomad
│   │       ├── jobs/     # Definiciones de jobs (.nomad)
│   │       ├── install.sls
│   │       ├── jobs.sls
│   │       └── deploy.sls
│   └── minion.conf       # Config para masterless
├── scripts/
│   ├── bootstrap.sh      # Bootstrap inicial del servidor
│   ├── deploy.sh         # Deploy de aplicaciones
│   └── configure-secrets.sh
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
sudo salt-call --local state.apply nomad.jobs
```

### Deploy de aplicaciones

```bash
# Deploy de una aplicación específica
sudo /srv/gdu_infra/scripts/deploy.sh gdu-usuarios
sudo /srv/gdu_infra/scripts/deploy.sh gdu-portal-proveedores

# Deploy de todas las aplicaciones
sudo /srv/gdu_infra/scripts/deploy.sh all
```

### Actualizar a una nueva versión

Las imágenes se publican automáticamente en GitHub Container Registry cuando se hace push a `main`. Para deployar la última versión:

```bash
# 1. Forzar pull de la imagen más reciente y restart del job
nomad job restart gdu-usuarios

# O hacer un redeploy completo
nomad job run /srv/gdu_infra/salt/states/nomad/jobs/gdu-usuarios.nomad
```

### Usar un branch específico del IdP (gdu_usuarios)

Si necesitas probar una versión del IdP desde un branch distinto a `main`:

1. **Verificar que la imagen del branch existe en ghcr.io**
   
   El CI genera imágenes con el nombre del branch como tag:
   ```
   ghcr.io/cyberplant/gdu_usuarios:nombre-del-branch
   ```

2. **Modificar temporalmente el job de Nomad**
   ```bash
   # Editar el archivo del job
   vim /srv/gdu_infra/salt/states/nomad/jobs/gdu-usuarios.nomad
   
   # Cambiar la línea de imagen de:
   #   image = "ghcr.io/cyberplant/gdu_usuarios:latest"
   # A:
   #   image = "ghcr.io/cyberplant/gdu_usuarios:mi-branch"
   ```

3. **Aplicar el cambio**
   ```bash
   nomad job run /srv/gdu_infra/salt/states/nomad/jobs/gdu-usuarios.nomad
   ```

4. **Para volver a main**, revertir el cambio y re-deployar:
   ```bash
   cd /srv/gdu_infra && git checkout salt/states/nomad/jobs/gdu-usuarios.nomad
   nomad job run /srv/gdu_infra/salt/states/nomad/jobs/gdu-usuarios.nomad
   ```

### Comandos Nomad útiles

```bash
# Ver todos los jobs
nomad job status

# Ver estado de un job específico
nomad job status gdu-usuarios

# Ver allocations de un job
nomad job allocs gdu-usuarios

# Ver logs de una allocation
nomad alloc logs -f <ALLOC_ID>

# Reiniciar un job (pull nueva imagen si existe)
nomad job restart gdu-usuarios

# Detener un job
nomad job stop gdu-usuarios

# Ver logs en tiempo real del último allocation
nomad alloc logs -f $(nomad job allocs -json gdu-usuarios | jq -r '.[0].ID')
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
