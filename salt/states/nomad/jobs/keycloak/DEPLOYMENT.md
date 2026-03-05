# Deployment: Keycloak Test Environment

## 📋 Comandos Rápidos

### Desplegar por primera vez

```bash
# 1. SSH al servidor
ssh usuario@servidor

# 2. Preparar volumen Nomad (solo primera vez)
sudo mkdir -p /opt/nomad/data/keycloak
sudo chown nomad:nomad /opt/nomad/data/keycloak

# 3. Agregar configuración de volumen a Nomad (si no existe)
sudo nano /etc/nomad.d/nomad.hcl
# Agregar en la sección client:
#   host_volume "keycloak-data" {
#     path      = "/opt/nomad/data/keycloak"
#     read_only = false
#   }

# 4. Reiniciar Nomad (solo si modificaste el archivo)
sudo systemctl restart nomad
sudo systemctl status nomad

# 5. Crear base de datos (solo primera vez)
psql -h 127.0.0.1 -p 5433 -U gdu_app -d postgres -c "CREATE DATABASE keycloak;"

# 6. Desplegar Keycloak
cd /ruta/a/infra/salt/states/nomad/jobs
nomad job run keycloak.nomad

# 7. Actualizar Traefik
nomad job run traefik.nomad

# 8. Verificar
nomad job status keycloak-test
curl -k https://keycloak.roar.uy/health/ready
```

### Actualizar configuración

```bash
# 1. Editar archivo
nano /ruta/a/infra/salt/states/nomad/jobs/keycloak.nomad

# 2. Verificar sintaxis
nomad job validate keycloak.nomad

# 3. Ver plan de cambios
nomad job plan keycloak.nomad

# 4. Aplicar cambios
nomad job run keycloak.nomad
```

### Ver estado y logs

```bash
# Status del job
nomad job status keycloak-test

# Listar allocations
nomad job allocs keycloak-test

# Logs en tiempo real
ALLOC_ID=$(nomad job allocs keycloak-test | grep running | awk '{print $1}')
nomad alloc logs -f $ALLOC_ID

# Logs stderr
nomad alloc logs -stderr -f $ALLOC_ID

# Ver eventos
nomad alloc status $ALLOC_ID
```

### Reiniciar

```bash
# Restart suave
nomad job restart keycloak-test

# Restart completo (destruye y recrea)
nomad job stop keycloak-test
nomad job run keycloak.nomad
```

### Detener

```bash
# Stop (mantiene datos)
nomad job stop keycloak-test

# Purge (elimina job completamente)
nomad job stop -purge keycloak-test
```

### Limpiar completamente

```bash
# 1. Detener job
nomad job stop -purge keycloak-test

# 2. Eliminar base de datos
psql -h 127.0.0.1 -p 5433 -U gdu_app -d postgres -c "DROP DATABASE keycloak;"

# 3. Limpiar volumen (CUIDADO: elimina todos los datos)
sudo rm -rf /opt/nomad/data/keycloak/*
```

## 🔍 Troubleshooting Commands

### Verificar conectividad de red

```bash
# Desde el host
curl http://127.0.0.1:8180/health/ready

# Desde dentro del container (si aplica)
nomad alloc exec $ALLOC_ID curl http://localhost:8180/health/ready
```

### Verificar base de datos

```bash
# Conectar a DB
psql -h 127.0.0.1 -p 5433 -U gdu_app -d keycloak

# Ver tablas
\dt

# Ver conexiones activas
SELECT * FROM pg_stat_activity WHERE datname = 'keycloak';
```

### Verificar Traefik routing

```bash
# Ver routers configurados
curl http://127.0.0.1:8080/api/http/routers | jq '.[] | select(.name | contains("keycloak"))'

# Ver services
curl http://127.0.0.1:8080/api/http/services | jq '.[] | select(.name | contains("keycloak"))'

# Test del routing
curl -H "Host: keycloak.roar.uy" http://127.0.0.1:80/health/ready
```

### Verificar volúmenes

```bash
# Ver contenido del volumen
ls -la /opt/nomad/data/keycloak/

# Permisos
ls -ld /opt/nomad/data/keycloak/
```

### Verificar recursos

```bash
# CPU y memoria del allocation
nomad alloc status $ALLOC_ID | grep -A 5 "Resources"

# Stats en tiempo real
nomad alloc status -stats $ALLOC_ID
```

## 📊 Monitoring

### Health checks

```bash
# Ready check (debería retornar 200)
curl -i https://keycloak.roar.uy/health/ready

# Live check
curl -i https://keycloak.roar.uy/health/live

# Metrics (si está habilitado)
curl -i https://keycloak.roar.uy/metrics
```

### Ver todos los logs

```bash
# Últimas 100 líneas
nomad alloc logs -n 100 $ALLOC_ID

# Buscar errores
nomad alloc logs $ALLOC_ID 2>&1 | grep -i error

# Buscar warnings
nomad alloc logs $ALLOC_ID 2>&1 | grep -i warn
```

## 🔐 Seguridad

### Cambiar password de admin

```bash
# Opción 1: Vía env var y redeploy
# Editar keycloak.nomad y cambiar:
# KEYCLOAK_ADMIN_PASSWORD = "new-secure-password"

# Opción 2: Vía admin console de Keycloak
# https://keycloak.roar.uy → Users → admin → Credentials
```

### Rotar client secret

Cuando termines el testing:

1. Ir a Django admin: https://auth.portalgdu.com.uy/admin/
2. OAuth2 Provider → Applications → Keycloak Test
3. Click en "Regenerate client secret"
4. Actualizar en Keycloak Identity Provider

## 📝 Logs útiles

### Ver OAuth flow completo

**Terminal 1 - Keycloak:**
```bash
nomad alloc logs -f $ALLOC_ID 2>&1 | grep -i "broker\|oauth\|token\|userinfo"
```

**Terminal 2 - IdP:**
```bash
docker logs -f gdu-usuarios-web-1 2>&1 | grep -i "oauth\|userinfo\|authorize"
```

### Filtrar por usuario específico

```bash
# En IdP
docker logs gdu-usuarios-web-1 2>&1 | grep "usuario@example.com"

# En Keycloak
nomad alloc logs $ALLOC_ID 2>&1 | grep "usuario@example.com"
```

## 🚀 Performance

### Ajustar recursos

Si Keycloak está lento o se queda sin memoria:

```hcl
# En keycloak.nomad
resources {
  cpu    = 2000  # Aumentar CPU
  memory = 2048  # Aumentar RAM
}
```

```bash
nomad job plan keycloak.nomad
nomad job run keycloak.nomad
```

## 🗑️ Después del testing

Cuando ya no necesites Keycloak:

```bash
# 1. Stop job
nomad job stop keycloak-test

# 2. Eliminar application del IdP
# https://auth.portalgdu.com.uy/admin/ → Applications → Keycloak Test → Delete

# 3. Eliminar DB (opcional)
psql -h 127.0.0.1 -p 5433 -U gdu_app -d postgres -c "DROP DATABASE keycloak;"

# 4. Eliminar volumen (opcional, libera espacio)
sudo rm -rf /opt/nomad/data/keycloak

# 5. Remover de Traefik (opcional)
# Comentar las líneas de keycloak en traefik.nomad
# nomad job run traefik.nomad
```

## 💡 Tips

- **Logs son tu amigo:** Siempre ten logs corriendo mientras pruebas
- **Usa job plan:** Revisa cambios antes de aplicar
- **Health checks:** Verifica que el servicio está ready antes de probar
- **DB connections:** Keycloak necesita conexión estable a Postgres
- **RAM:** Keycloak usa ~1GB, asegúrate de tener recursos suficientes
