# Quick Reference: Keycloak Test Setup

## 🚀 Deploy en 5 minutos

```bash
# 1. SSH al servidor
ssh usuario@servidor

# 2. Preparar (solo primera vez)
sudo mkdir -p /opt/nomad/data/keycloak
sudo chown nomad:nomad /opt/nomad/data/keycloak
psql -h 127.0.0.1 -p 5433 -U gdu_app -d postgres -c "CREATE DATABASE keycloak;"

# 3. Deploy
cd /ruta/a/infra/salt/states/nomad/jobs
nomad job run keycloak.nomad
nomad job run traefik.nomad  # Actualizar routing

# 4. Verificar
nomad job status keycloak-test
curl -k https://keycloak.roar.uy/health/ready
```

## 🔗 URLs

- **Keycloak:** https://keycloak.roar.uy (admin/admin)
- **IdP:** https://auth.portalgdu.com.uy

## 📋 Configurar integración

### En IdP (Django admin)
```
URL: https://auth.portalgdu.com.uy/admin/
→ OAuth2 Provider → Applications → Add

Name: Keycloak Test
Client type: Confidential
Authorization grant type: Authorization code
Redirect URIs:
  https://keycloak.roar.uy/realms/master/broker/gdu-idp/endpoint
```

### En Keycloak
```
URL: https://keycloak.roar.uy
→ Identity Providers → OpenID Connect v1.0

Discovery endpoint:
  https://auth.portalgdu.com.uy/o/.well-known/openid-configuration

Import → Agregar Client ID y Secret → Save
```

## 🧪 Probar

1. Logout de Keycloak admin
2. Try to log in → Aparece botón "gdu-idp"
3. Click → Login en IdP → Redirige a Keycloak ✅

## 🐛 Debug

```bash
# Ver logs
ALLOC=$(nomad job allocs keycloak-test | grep running | awk '{print $1}')
nomad alloc logs -f $ALLOC

# Ver ambos logs simultáneamente
nomad alloc logs -f $ALLOC &
docker logs -f gdu-usuarios-web-1
```

## 🗑️ Limpiar

```bash
nomad job stop keycloak-test
# Eliminar Application del IdP admin
```

## 📖 Documentación completa

- `keycloak/README.md` - Overview y troubleshooting
- `keycloak/SETUP.md` - Configuración paso a paso
- `keycloak/DEPLOYMENT.md` - Comandos y operaciones
