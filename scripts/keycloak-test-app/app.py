"""
App mínima para testear el flujo OIDC completo contra Keycloak.
Requiere un Client registrado en Keycloak (ver README.md).
"""
import os
import secrets
import json
import urllib.parse
import urllib.request
import http.server
import webbrowser

# ── Configuración ──────────────────────────────────────────────────────────────
KEYCLOAK_BASE    = os.getenv("KEYCLOAK_BASE",    "https://keycloak.roar.uy")
REALM            = os.getenv("REALM",            "master")
CLIENT_ID        = os.getenv("CLIENT_ID",        "test-app")
CLIENT_SECRET    = os.getenv("CLIENT_SECRET",    "")        # dejar vacío si es public client
IDP_HINT         = os.getenv("IDP_HINT",         "gdu-analytics")  # alias del Identity Provider en KC
PORT             = int(os.getenv("PORT",         "5000"))

REDIRECT_URI     = f"http://localhost:{PORT}/callback"
BASE_URL         = f"{KEYCLOAK_BASE}/realms/{REALM}/protocol/openid-connect"
AUTH_URL         = f"{BASE_URL}/auth"
TOKEN_URL        = f"{BASE_URL}/token"
USERINFO_URL     = f"{BASE_URL}/userinfo"
LOGOUT_URL       = f"{BASE_URL}/logout"

# Estado global mínimo (solo para testing local, no usar en producción)
_state = {}


def build_auth_url():
    state = secrets.token_urlsafe(16)
    _state["state"] = state
    params = {
        "client_id":     CLIENT_ID,
        "redirect_uri":  REDIRECT_URI,
        "response_type": "code",
        "scope":         "openid profile email",
        "state":         state,
        "kc_idp_hint":   IDP_HINT,   # fuerza ir directo al IdP sin pasar por la pantalla de KC
    }
    return AUTH_URL + "?" + urllib.parse.urlencode(params)


def exchange_code(code):
    data = {
        "grant_type":   "authorization_code",
        "code":         code,
        "redirect_uri": REDIRECT_URI,
        "client_id":    CLIENT_ID,
    }
    if CLIENT_SECRET:
        data["client_secret"] = CLIENT_SECRET

    body = urllib.parse.urlencode(data).encode()
    req  = urllib.request.Request(TOKEN_URL, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def get_userinfo(access_token):
    req = urllib.request.Request(USERINFO_URL)
    req.add_header("Authorization", f"Bearer {access_token}")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def decode_jwt_payload(token):
    """Decodifica el payload del JWT sin verificar firma (solo para debug)."""
    try:
        payload_b64 = token.split(".")[1]
        # Agregar padding faltante
        payload_b64 += "=" * (-len(payload_b64) % 4)
        import base64
        return json.loads(base64.urlsafe_b64decode(payload_b64))
    except Exception:
        return {}


def html_page(title, body):
    return f"""<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>{title}</title>
  <style>
    body {{ font-family: monospace; max-width: 900px; margin: 40px auto; padding: 0 20px; background: #1e1e1e; color: #d4d4d4; }}
    h1   {{ color: #569cd6; }}
    h2   {{ color: #4ec9b0; margin-top: 2em; }}
    pre  {{ background: #252526; padding: 16px; border-radius: 6px; overflow-x: auto; white-space: pre-wrap; word-break: break-all; }}
    a    {{ display: inline-block; margin: 8px 4px; padding: 10px 20px; background: #0e639c; color: white; text-decoration: none; border-radius: 4px; }}
    a:hover {{ background: #1177bb; }}
    .error {{ color: #f48771; }}
    .label {{ color: #9cdcfe; }}
  </style>
</head>
<body>{body}</body>
</html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"  → {fmt % args}")

    def send_html(self, content, status=200):
        encoded = content.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        qs     = urllib.parse.parse_qs(parsed.query)
        path   = parsed.path

        # ── / ─────────────────────────────────────────────────────────────────
        if path == "/":
            auth_url = build_auth_url()
            body = f"""
<h1>🔑 Keycloak Test App</h1>
<p>Esta app dispara el flujo OIDC completo:</p>
<ol>
  <li>Vos → Keycloak (Authorization Request)</li>
  <li>Keycloak → IdP <strong>{IDP_HINT}</strong> (redirección automática por <code>kc_idp_hint</code>)</li>
  <li>Hacés login en el IdP</li>
  <li>IdP → Keycloak (callback con <code>code</code>)</li>
  <li>Keycloak → esta app (callback con <code>code</code>)</li>
  <li>Esta app intercambia el <code>code</code> por tokens y muestra el resultado</li>
</ol>
<a href="{auth_url}">🚀 Iniciar Login con {IDP_HINT}</a>
<a href="/login-kc">🔐 Login directo Keycloak (sin hint)</a>
<hr>
<p style="color:#888">Config: <code>realm={REALM}</code> <code>client_id={CLIENT_ID}</code> <code>idp={IDP_HINT}</code></p>
"""
            self.send_html(html_page("Test App", body))

        # ── /login-kc ─────────────────────────────────────────────────────────
        elif path == "/login-kc":
            state = secrets.token_urlsafe(16)
            _state["state"] = state
            params = {
                "client_id":     CLIENT_ID,
                "redirect_uri":  REDIRECT_URI,
                "response_type": "code",
                "scope":         "openid profile email",
                "state":         state,
            }
            url = AUTH_URL + "?" + urllib.parse.urlencode(params)
            self.send_response(302)
            self.send_header("Location", url)
            self.end_headers()

        # ── /callback ─────────────────────────────────────────────────────────
        elif path == "/callback":
            if "error" in qs:
                error = qs.get("error", ["?"])[0]
                desc  = qs.get("error_description", [""])[0]
                body  = f"""<h1 class="error">❌ Error del IdP</h1>
<p><span class="label">error:</span> <code>{error}</code></p>
<p><span class="label">description:</span> <code>{desc}</code></p>
<a href="/">← Volver</a>"""
                self.send_html(html_page("Error", body))
                return

            code     = qs.get("code", [None])[0]
            returned = qs.get("state", [None])[0]

            if not code:
                self.send_html(html_page("Error", '<p class="error">No llegó code en el callback.</p><a href="/">← Volver</a>'))
                return

            if returned != _state.get("state"):
                self.send_html(html_page("Error", '<p class="error">State mismatch — posible CSRF.</p><a href="/">← Volver</a>'))
                return

            # Intercambiar code por tokens
            try:
                tokens   = exchange_code(code)
                userinfo = get_userinfo(tokens["access_token"])
                id_claims = decode_jwt_payload(tokens.get("id_token", ""))
            except Exception as e:
                body = f"""<h1 class="error">❌ Error intercambiando tokens</h1>
<pre>{e}</pre>
<a href="/">← Volver</a>"""
                self.send_html(html_page("Error", body))
                return

            logout_url = (
                LOGOUT_URL
                + "?"
                + urllib.parse.urlencode({
                    "post_logout_redirect_uri": f"http://localhost:{PORT}/",
                    "client_id": CLIENT_ID,
                    "id_token_hint": tokens.get("id_token", ""),
                })
            )

            body = f"""
<h1>✅ Login exitoso!</h1>

<h2>👤 UserInfo (del IdP via Keycloak)</h2>
<pre>{json.dumps(userinfo, indent=2, ensure_ascii=False)}</pre>

<h2>🎫 ID Token claims (decoded)</h2>
<pre>{json.dumps(id_claims, indent=2, ensure_ascii=False)}</pre>

<h2>🔑 Tokens</h2>
<pre>{json.dumps({k: v for k, v in tokens.items() if k != "access_token"}, indent=2, ensure_ascii=False)}</pre>
<details>
  <summary style="cursor:pointer;color:#888">Access Token (raw)</summary>
  <pre style="font-size:0.75em">{tokens.get("access_token","")}</pre>
</details>

<a href="{logout_url}">🚪 Logout</a>
<a href="/">← Inicio</a>
"""
            self.send_html(html_page("Login OK", body))

        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    print(f"""
╔══════════════════════════════════════════════════════╗
║          Keycloak OIDC Test App                      ║
╠══════════════════════════════════════════════════════╣
║  Keycloak : {KEYCLOAK_BASE:<42}║
║  Realm    : {REALM:<42}║
║  Client   : {CLIENT_ID:<42}║
║  IdP hint : {IDP_HINT:<42}║
╚══════════════════════════════════════════════════════╝

Antes de arrancar, asegurate de tener en Keycloak un Client con:
  Client ID    : {CLIENT_ID}
  Redirect URI : {REDIRECT_URI}

Abriendo http://localhost:{PORT} ...
""")
    webbrowser.open(f"http://localhost:{PORT}")
    server = http.server.HTTPServer(("localhost", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDetenido.")
