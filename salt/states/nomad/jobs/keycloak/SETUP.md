# Setup: Configurar Keycloak con GDU IdP

## 🎯 Objetivo

Configurar Keycloak para usar GDU Usuarios como Identity Provider (IdP) via OAuth2/OIDC y reproducir/solucionar el error reportado por el cliente.

## 📋 Prerequisitos

- ✅ Keycloak corriendo en https://keycloak.roar.uy
- ✅ GDU IdP corriendo en https://auth.portalgdu.com.uy
- ✅ Acceso admin a ambos sistemas

## 🔑 Paso 1: Crear Application OAuth2 en GDU IdP

1. **Acceder al admin de Django:**
   ```
   https://auth.portalgdu.com.uy/admin/
   ```

2. **Navegar a:** OAuth2 Provider → Applications → Add application

3. **Configurar:**
   ```
   Name: Keycloak Test
   Client type: Confidential
   Authorization grant type: Authorization code
   
   Redirect URIs: (una por línea)
   https://keycloak.roar.uy/realms/master/broker/gdu-idp/endpoint
   https://keycloak.roar.uy/realms/test/broker/gdu-idp/endpoint
   
   Algorithm: No OIDC support (dejar vacío)
   ```

4. **Guardar y anotar:**
   - Client ID: `[COPIAR_VALOR]`
   - Client secret: `[COPIAR_VALOR]`

## 🔧 Paso 2: Configurar Identity Provider en Keycloak

### 2.1 Acceder a Keycloak Admin

1. **URL:** https://keycloak.roar.uy
2. **Login:** admin / admin
3. **Realm:** Master (o crear uno nuevo llamado "test")

### 2.2 Agregar Identity Provider

1. **Navegar a:** Identity Providers

2. **Click:** "Add provider" → **"OpenID Connect v1.0"**

3. **Configurar con Discovery (Recomendado):**
   
   ```
   Alias: gdu-idp
   Display name: GDU Portal
   
   OpenID Connect Config - Discovery endpoint:
   https://auth.portalgdu.com.uy/o/.well-known/openid-configuration
   ```
   
   **Click "Import"** - Esto auto-completará:
   - Authorization URL
   - Token URL
   - Logout URL
   - User Info URL ← Este es el que estaba fallando
   - Issuer

4. **Completar credenciales:**
   ```
   Client ID: [PEGAR_CLIENT_ID_DEL_PASO_1]
   Client Secret: [PEGAR_CLIENT_SECRET_DEL_PASO_1]
   ```

5. **Configurar Scopes:**
   ```
   Default Scopes: openid profile email
   ```

6. **Opciones adicionales (recomendadas):**
   ```
   ✓ Store tokens (para debugging)
   ✓ Stored tokens readable (para ver tokens)
   ✓ Trust email
   ✓ First login flow: first broker login
   ```

7. **Guardar**

### 2.3 Alternativa: Configuración Manual

Si Discovery no funciona, configurar manualmente:

```
Alias: gdu-idp
Display name: GDU Portal

Authorization URL: https://auth.portalgdu.com.uy/o/authorize/
Token URL: https://auth.portalgdu.com.uy/o/token/
Logout URL: https://auth.portalgdu.com.uy/logout/
User Info URL: https://auth.portalgdu.com.uy/o/userinfo/
Issuer: https://auth.portalgdu.com.uy

Client ID: [TU_CLIENT_ID]
Client Secret: [TU_CLIENT_SECRET]

Default Scopes: openid profile email
```

## 🧪 Paso 3: Testing

### 3.1 Test Básico

1. **Logout de Keycloak admin** (click en "admin" → "Sign out")

2. **Ir a login page:** https://keycloak.roar.uy/realms/master/account

3. **Debería aparecer:** Botón "GDU Portal" o "gdu-idp"

4. **Click en el botón** → Redirige a auth.portalgdu.com.uy

5. **Login con usuario GDU** → Redirige de vuelta a Keycloak

6. **Verificar:** Estás logueado en Keycloak con datos del IdP

### 3.2 Verificar Datos de Usuario

1. En Keycloak, ir a: **Users** → Buscar tu usuario

2. Verificar que se creó correctamente

3. Ver **Attributes** - Deberían estar los datos del IdP

## 🐛 Debugging

### Ver logs en tiempo real

**Terminal 1 - IdP:**
```bash
# En el servidor
docker logs -f gdu-usuarios-web-1
```

**Terminal 2 - Keycloak:**
```bash
# En el servidor
nomad alloc logs -f $(nomad job allocs keycloak-test | grep running | awk '{print $1}')
```

### Verificar OIDC Discovery

```bash
curl https://auth.portalgdu.com.uy/o/.well-known/openid-configuration | jq .
```

Verificar que `userinfo_endpoint` es:
```json
"userinfo_endpoint": "https://auth.portalgdu.com.uy/o/userinfo/"
```

### Test manual del UserInfo endpoint

```bash
# 1. Obtener token (necesitas client_id, client_secret y user credentials)
TOKEN=$(curl -X POST https://auth.portalgdu.com.uy/o/token/ \
  -d "grant_type=password" \
  -d "username=test@example.com" \
  -d "password=password" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "scope=openid profile email" | jq -r .access_token)

# 2. Probar userinfo
curl -H "Authorization: Bearer $TOKEN" \
  https://auth.portalgdu.com.uy/o/userinfo/ | jq .
```

**Verificar respuesta:**
- ✅ Debe tener campo `sub` (string)
- ✅ Content-Type: application/json
- ✅ Sin campos null

### Si falla el userinfo endpoint

**Síntomas comunes:**

1. **Error "Could not fetch attributes"**
   - Ver logs del IdP cuando Keycloak hace el request
   - Verificar que el token es válido
   - Verificar que el endpoint retorna JSON

2. **Error de SSL/TLS**
   - Verificar certificado Let's Encrypt
   - Keycloak podría no confiar en el cert

3. **Timeout**
   - Verificar conectividad de red
   - Keycloak debe poder alcanzar auth.portalgdu.com.uy

### Logs específicos en IdP

```bash
# Ver requests al userinfo
docker logs gdu-usuarios-web-1 2>&1 | grep -i "userinfo"

# Ver errores OAuth2
docker logs gdu-usuarios-web-1 2>&1 | grep -i "oauth\|token"

# Ver todos los requests
docker logs gdu-usuarios-web-1 2>&1 | tail -100
```

### Logs específicos en Keycloak

```bash
# Ver errores del identity provider
nomad alloc logs $(nomad job allocs keycloak-test | grep running | awk '{print $1}') 2>&1 | grep -i "identity\|broker\|userinfo"
```

## 📊 Comparar con Cliente

Una vez que reproduzcas el comportamiento (éxito o fallo):

1. **Exportar configuración de Keycloak:**
   - Identity Providers → gdu-idp → Export

2. **Comparar** con la configuración del cliente

3. **Identificar diferencias** y ajustar

## ✅ Validación Final

Para considerar el test exitoso:

- ✅ Login flow completo funciona
- ✅ Datos de usuario se sincronizan correctamente
- ✅ No errores en logs de ambos sistemas
- ✅ Puedes hacer logout y volver a login

## 🔄 Reintentar configuración

Si algo falla y quieres empezar de nuevo:

1. **En Keycloak:** Eliminar el Identity Provider
2. **En IdP:** Eliminar o regenerar Client Secret
3. **Repetir pasos** desde el inicio

## 💡 Tips

- **Usa realm separado:** Crea un realm "test" para no afectar "master"
- **Store tokens:** Facilita debugging (puedes ver los tokens)
- **Trust email:** Evita verificación adicional de email
- **Logs verbosos:** Activa debug en ambos sistemas si es necesario

## 📞 Soporte

Si encuentras un bug en el IdP durante este testing:
1. Documentar el error exacto
2. Capturar logs de ambos lados
3. Crear fix y testearlo inmediatamente aquí
4. Push y deploy cuando funcione
