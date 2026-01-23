# Configuración de firewall con UFW
{% set fw = pillar.get('firewall', {}) %}
{% if fw.get('enabled', true) %}

ufw_installed:
  pkg.installed:
    - name: ufw

ufw_default_deny:
  cmd.run:
    - name: ufw default deny incoming
    - unless: ufw status verbose | grep -q "Default: deny (incoming)"
    - require:
      - pkg: ufw_installed

ufw_default_allow_out:
  cmd.run:
    - name: ufw default allow outgoing
    - unless: ufw status verbose | grep -q "Default: allow (outgoing)"
    - require:
      - pkg: ufw_installed

{% for port in fw.get('allowed_ports', ['22/tcp']) %}
ufw_allow_{{ port | replace('/', '_') }}:
  cmd.run:
    - name: ufw allow {{ port }}
    - unless: ufw status | grep -q "{{ port.split('/')[0] }}"
    - require:
      - cmd: ufw_default_deny
{% endfor %}

ufw_enable:
  cmd.run:
    - name: ufw --force enable
    - unless: ufw status | grep -q "Status: active"
    - require:
      - cmd: ufw_default_deny

{% endif %}
