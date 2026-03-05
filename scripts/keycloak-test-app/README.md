# Keycloak OIDC Test App

App mínima (stdlib Python, sin dependencias) para testear el flujo OIDC completo contra Keycloak + GDU IdP.

## Paso 1 — Registrar Client en Keycloak

1. Ir a https://keycloak.roar.uy → Admin → Realm `master` → **Clients** → **Create client**
2. Configurar:
   ```
   Client type      : OpenID Connect
   Client ID        : test-app
   ```
3. Next → habilitar **Standard flow** (Authorization Code) → Next
4. Set redirect URI:
   ```
   Valid redirect URIs: http://localhost:5000/callback
   Web origins:        http://localhost:5000
   ```
5. Save

> Si querés client secret (confidential): en la pestaña **Credentials** copiá el secret y pasalo como `CLIENT_SECRET`.

## Paso 2 — Correr la app

```bash
cd scripts/keycloak-test-app

# Opciones por variable de entorno (los defaults ya apuntan a keycloak.roar.uy)
python app.py

# O con configuración explícita:
CLIENT_SECRET=xxx python app.py

# Cambiar el alias del IdP si lo registraste con otro nombre:
IDP_HINT=gdu-analytics python app.py
```

Se abre el browser en `http://localhost:5000` automáticamente.

## Qué hace

```
Browser → /  →  Keycloak /auth?kc_idp_hint=gdu-analytics
                    ↓
              Keycloak redirige DIRECTO al IdP (sin pantalla intermedia)
                    ↓
              Login en auth.portalgdu.com.uy
                    ↓
              IdP callback → Keycloak /broker/gdu-analytics/endpoint
                    ↓
              Keycloak callback → /callback?code=...
                    ↓
              App intercambia code → tokens
                    ↓
              Muestra UserInfo + ID Token claims + tokens
```

## Variables de entorno

| Variable       | Default                    | Descripción                          |
|----------------|----------------------------|--------------------------------------|
| `KEYCLOAK_BASE`| `https://keycloak.roar.uy` | URL base de Keycloak                 |
| `REALM`        | `master`                   | Realm a usar                         |
| `CLIENT_ID`    | `test-app`                 | Client ID registrado en Keycloak     |
| `CLIENT_SECRET`| `""`                       | Secret (dejar vacío si es public)    |
| `IDP_HINT`     | `gdu-analytics`            | Alias del Identity Provider en KC   |
| `PORT`         | `5000`                     | Puerto local                         |
