# Firewall - DESHABILITADO
# El servidor usa firehol que ya está configurado manualmente
# No gestionamos el firewall desde Salt para no interferir

firewall_placeholder:
  test.nop:
    - name: "Firewall gestionado externamente (firehol)"
