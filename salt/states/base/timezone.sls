# Configuración de zona horaria
timezone_set:
  timezone.system:
    - name: {{ pillar.get('timezone', 'America/Montevideo') }}
