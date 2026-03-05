# Keycloak Test Environment

Este directorio contiene la configuración para levantar Keycloak en el servidor para testing de integración OAuth2/OIDC con el IdP de GDU Usuarios.

## 📋 Archivos

- `../keycloak.nomad` - Job de Nomad para Keycloak
- `README.md` - Este archivo
- `SETUP.md` - Guía de configuración paso a paso
- `TESTING.md` - Guía de testing y debugging

## 🚀 Quick Start

### 1. Asegurar volumen host en Nomad

En el servidor, verificar que existe el volumen:

```bash
# Ver configuración de Nomad
cat /etc/nomad.d/nomad.hcl | grep -A 10 "host_volume"
```

Si no existe `keycloak-data`, agregarlo:

```hcl
# /etc/nomad.d/nomad.hcl
client {
  host_volume "keycloak-data" {
    path      = "/opt/nomad/data/keycloak"
    read_only = false
  }
}
```

```bash
# Crear directorio
sudo mkdir -p /opt/nomad/data/keycloak
sudo chown nomad:nomad /opt/nomad/data/keycloak

# Reiniciar Nomad
sudo systemctl restart nomad
```

### 2. Crear base de datos

Keycloak necesita su propia base de datos en Postgres:

```bash
# Conectar a Postgres
psql -h 127.0.0.1 -p 5433 -U gdu_app -d postgres

# Crear base de datos
CREATE DATABASE keycloak;

# Verificar
\l keycloak
\q
```

### 3. Desplegar Keycloak

```bash
cd /path/to/infra/salt/states/nomad/jobs

# Planear
nomad job plan keycloak.nomad

# Desplegar
nomad job run keycloak.nomad

# Ver status
nomad job status keycloak-test

# Ver logs
nomad alloc logs -f $(nomad job allocs keycloak-test | grep running | awk '{print $1}')
```

### 4. Re-desplegar Traefik

Para que Traefik recoja las nuevas rutas:

```bash
# Planear
nomad job plan traefik.nomad

# Desplegar
nomad job run traefik.nomad
```

### 5. Acceder

- **URL:** https://keycloak.roar.uy
- **Usuario:** admin
- **Password:** admin

## 🔍 Verificación

```bash
# Verificar que Keycloak está corriendo
curl -k https://keycloak.roar.uy/health/ready

# Ver logs en tiempo real
nomad alloc logs -f $(nomad job allocs keycloak-test | grep running | awk '{print $1}')

# Verificar Traefik
curl http://127.0.0.1:8080/api/http/routers
```

## 🐛 Troubleshooting

### Keycloak no inicia

```bash
# Ver logs completos
nomad alloc logs $(nomad job allocs keycloak-test | grep -v complete | tail -1 | awk '{print $1}')

# Ver status detallado
nomad alloc status $(nomad job allocs keycloak-test | grep -v complete | tail -1 | awk '{print $1}')
```

### No se puede conectar a la DB

Verificar que:
1. PostgreSQL está corriendo en puerto 5433
2. La base de datos `keycloak` existe
3. Las credenciales son correctas

```bash
# Test de conexión
psql -h 127.0.0.1 -p 5433 -U gdu_app -d keycloak -c "SELECT 1;"
```

### SSL no funciona

```bash
# Ver certificados de Let's Encrypt
docker exec traefik cat /letsencrypt/acme.json | jq '.letsencrypt.Certificates[] | .domain'

# Ver logs de Traefik
docker logs traefik | grep keycloak
```

## 📝 Próximos Pasos

Ver `SETUP.md` para configuración detallada de la integración con el IdP.
