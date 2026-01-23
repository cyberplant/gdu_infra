# SSH - DESHABILITADO
# El servidor ya tiene SSH configurado en puertos 999 y 7822
# No gestionamos SSH desde Salt para no interferir

ssh_placeholder:
  test.nop:
    - name: "SSH gestionado externamente"
