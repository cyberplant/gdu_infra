# ==============================================================
# TEMPORAL - Mock del endpoint /o/userinfo para pruebas
#
# Para REMOVER:
#   1. Eliminar este archivo (mock-userinfo.nomad)
#   2. En traefik.nomad, eliminar las secciones marcadas con
#      "# TEMPORAL mock-userinfo" en routers y services
#   3. Hacer: nomad job stop mock-userinfo
# ==============================================================

job "mock-userinfo" {
  datacenters = ["dc1"]
  type        = "service"

  group "mock-userinfo" {
    count = 1

    network {
      port "http" {
        static = 19999
      }
    }

    task "server" {
      driver = "docker"

      config {
        image        = "python:3.12-alpine"
        network_mode = "host"
        entrypoint   = ["python3"]
        args         = ["/local/server.py"]

        volumes = [
          "local/server.py:/local/server.py"
        ]
      }

      template {
        destination = "local/server.py"
        data        = <<-EOF
        from http.server import HTTPServer, BaseHTTPRequestHandler

        USERINFO_JSON = b'''{
          "sub": "b2d2d115-1d7e-4579-b9d6-f8e84f4f56ca",
          "name": "John Smith",
          "given_name": "John",
          "family_name": "Smith",
          "nickname": "Johnny",
          "preferred_username": "jsmith",
          "profile": "http://example.com",
          "picture": "http://example.com/pic.png",
          "website": "http://example.com",
          "email": "test@example.com",
          "email_verified": true,
          "gender": "male",
          "birthdate": "1970-01-01",
          "zoneinfo": "America/Los_Angeles",
          "locale": "en-US",
          "phone_number": "+1 (425) 555-1212",
          "phone_number_verified": true,
          "address": {
            "formatted": "123 Main St Apt 123\\nWashington, DC 20001",
            "street_address": "123 Main St Apt 123",
            "locality": "Washington",
            "region": "DC",
            "postal_code": "20001",
            "country": "US"
          },
          "updated_at": 1577854800
        }'''

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(USERINFO_JSON)))
                self.end_headers()
                self.wfile.write(USERINFO_JSON)

            def log_message(self, format, *args):
                pass  # suprimir logs del servidor

        HTTPServer(('127.0.0.1', 19999), Handler).serve_forever()
        EOF
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
