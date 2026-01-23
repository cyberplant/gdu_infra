# Configuración Nomad
nomad:
  version: "1.7.3"
  datacenter: dc1

# Dominios configurados
domains:
  gdu_usuarios:
    - usuarios.portalgdu.com.uy
    - auth.portalgdu.com.uy
  gdu_proveedores:
    - proveedores.gdu.uy
    - proveedores.portalgdu.com.uy
  grafana:
    - grafana.portalgdu.com.uy

# Email para Let's Encrypt
letsencrypt_email: luar@roar.uy
