# Instalación de paquetes base
base_packages:
  pkg.installed:
    - pkgs: {{ pillar.get('base_packages', []) }}
    - refresh: true
