# Estado Salt para deploy/update de aplicaciones Nomad
# Uso: salt-call --local state.apply nomad.deploy pillar='{"app": "gdu-usuarios"}'
# O para todas: salt-call --local state.apply nomad.deploy pillar='{"app": "all"}'

{% set nomad_jobs_path = "/srv/gdu_infra/salt/states/nomad/jobs" %}
{% set app = salt['pillar.get']('app', 'all') %}
{% set apps = ['gdu-usuarios', 'gdu-portal-proveedores'] %}

{% if app != 'all' %}
  {% set apps = [app] %}
{% endif %}

{% for app_name in apps %}
# Pull de la última imagen
pull_{{ app_name }}:
  cmd.run:
    - name: docker pull ghcr.io/cyberplant/{{ app_name | replace('-', '_') }}:latest
    - timeout: 300

# Stop del job actual
stop_{{ app_name }}:
  cmd.run:
    - name: /usr/local/bin/nomad job stop -purge {{ app_name }} || true
    - require:
      - cmd: pull_{{ app_name }}

# Esperar a que el job se detenga
wait_stop_{{ app_name }}:
  cmd.run:
    - name: |
        for i in $(seq 1 30); do
          if ! /usr/local/bin/nomad job status {{ app_name }} 2>/dev/null | grep -q "Status.*running"; then
            exit 0
          fi
          sleep 1
        done
        exit 0
    - timeout: 60
    - require:
      - cmd: stop_{{ app_name }}

# Iniciar el job con la nueva imagen
start_{{ app_name }}:
  cmd.run:
    - name: /usr/local/bin/nomad job run {{ nomad_jobs_path }}/{{ app_name }}.nomad
    - require:
      - cmd: wait_stop_{{ app_name }}

# Verificar que el job está corriendo
verify_{{ app_name }}:
  cmd.run:
    - name: |
        for i in $(seq 1 60); do
          if /usr/local/bin/nomad job status {{ app_name }} 2>/dev/null | grep -q "Status.*running"; then
            echo "✓ {{ app_name }} está corriendo"
            exit 0
          fi
          sleep 2
        done
        echo "✗ {{ app_name }} no levantó después de 2 minutos"
        exit 1
    - timeout: 180
    - require:
      - cmd: start_{{ app_name }}

{% endfor %}
