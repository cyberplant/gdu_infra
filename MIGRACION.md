# Plan de Migración a Nomad

## Estado Actual

### Sistemas Legacy (Docker directo + Nginx)

| Sistema | Puerto | Dominios | Estado |
|---------|--------|----------|--------|
| portal_gdu | 8000 | proveedores.gdu.uy, www.proveedores.gdu.uy | Mantener |
| meeting_room_manager | 8001 | gestiones.portalgdu.com.uy, gduprod.roar.uy | Mantener |

### Sistemas Nuevos (Nomad)

| Sistema | Puerto | Dominios | Estado |
|---------|--------|----------|--------|
| gdu-usuarios | 8010 | usuarios.portalgdu.com.uy, auth.portalgdu.com.uy | Nuevo |
| gdu-portal-proveedores | 8011 | proveedores.portalgdu.com.uy | Nuevo |
| grafana | 3000 | grafana.portalgdu.com.uy | Nuevo |
| postgres | 5432 | - | Nuevo |

## Plan de Migración

### Paso 1: Preparación (sin downtime)

```bash
# En el servidor, clonar el repo
cd /srv
git clone git@github.com:cyberplant/gdu_infra.git

# Instalar Nomad (sin afectar nada existente)
bash /srv/gdu_infra/scripts/bootstrap.sh
# Esto instala Nomad pero NO para nginx aún
```

### Paso 2: Verificar Nomad funcionando

```bash
# Verificar que Nomad está corriendo
nomad server members
nomad job status

# Verificar que Traefik NO está escuchando aún en 80/443
# (porque Nginx aún los usa)
```

### Paso 3: Configurar secrets

```bash
# PostgreSQL
nomad var put nomad/jobs/postgres \
  postgres_password="PASSWORD_SEGURO"

# Apps
nomad var put nomad/jobs/gdu-usuarios \
  db_password="PASSWORD" \
  django_secret_key="SECRET_KEY_50_CHARS"

nomad var put nomad/jobs/gdu-portal-proveedores \
  db_password="PASSWORD" \
  django_secret_key="SECRET_KEY_50_CHARS"
```

### Paso 4: Login a ghcr.io

```bash
echo "GITHUB_TOKEN" | docker login ghcr.io -u cyberplant --password-stdin
```

### Paso 5: Desplegar servicios nuevos (sin Traefik aún)

```bash
# Desplegar PostgreSQL y apps en sus puertos internos
nomad job run /srv/gdu_infra/nomad/postgres.nomad
nomad job run /srv/gdu_infra/nomad/postgres-init.nomad
nomad job run /srv/gdu_infra/nomad/gdu-usuarios.nomad
nomad job run /srv/gdu_infra/nomad/gdu-portal-proveedores.nomad
nomad job run /srv/gdu_infra/nomad/monitoring.nomad

# Verificar que están corriendo
nomad job status
curl http://localhost:8010/health/  # gdu-usuarios
curl http://localhost:8011/health/  # gdu-portal-proveedores
```

### Paso 6: El cambio (downtime mínimo ~30 segundos)

```bash
# 1. Parar Nginx
systemctl stop nginx

# 2. Desplegar Traefik (toma los puertos 80/443)
nomad job run /srv/gdu_infra/nomad/traefik.nomad

# 3. Verificar que todo funciona
curl -I https://proveedores.gdu.uy          # Legacy
curl -I https://gestiones.portalgdu.com.uy  # Legacy
curl -I https://usuarios.portalgdu.com.uy   # Nuevo
```

### Paso 7: Verificación post-migración

```bash
# Ver estado de todos los jobs
nomad job status

# Ver logs si hay problemas
nomad alloc logs -f $(nomad job allocs traefik | tail -1 | awk '{print $1}')

# Ver dashboard de Traefik
# http://servidor:8080
```

## Rollback (si algo falla)

```bash
# Parar Traefik
nomad job stop traefik

# Reiniciar Nginx
systemctl start nginx

# Los legacy siguen funcionando como antes
```

## Mapa de Puertos

```
Puerto  | Servicio              | Tipo
--------|----------------------|-------
80      | Traefik (HTTP)       | Nomad
443     | Traefik (HTTPS)      | Nomad
3000    | Grafana              | Nomad
5432    | PostgreSQL           | Legacy (OS)
5433    | PostgreSQL           | Nomad
8000    | portal_gdu           | Legacy
8001    | meeting_room_manager | Legacy
8010    | gdu-usuarios         | Nomad
8011    | gdu-portal-proveedores| Nomad
8080    | Traefik Dashboard    | Nomad
9090    | Prometheus           | Nomad
```

## Dominios y Routing

```
Dominio                        → Servicio              → Puerto
proveedores.gdu.uy            → legacy-portal-gdu     → 8000
www.proveedores.gdu.uy        → legacy-portal-gdu     → 8000
gestiones.portalgdu.com.uy    → legacy-meeting-room   → 8001
gduprod.roar.uy               → legacy-meeting-room   → 8001
usuarios.portalgdu.com.uy     → gdu-usuarios          → 8010
auth.portalgdu.com.uy         → gdu-usuarios          → 8010
proveedores.portalgdu.com.uy  → gdu-portal-proveedores→ 8011
grafana.portalgdu.com.uy      → grafana               → 3000
```
