# Gestión de usuarios administradores
{% for username, user_data in pillar.get('admin_users', {}).items() %}

{{ username }}_user:
  user.present:
    - name: {{ username }}
    - fullname: {{ user_data.get('fullname', username) }}
    - shell: /bin/bash
    - home: /home/{{ username }}
    - createhome: true
    - groups: {{ user_data.get('groups', ['sudo']) }}

{{ username }}_ssh_dir:
  file.directory:
    - name: /home/{{ username }}/.ssh
    - user: {{ username }}
    - group: {{ username }}
    - mode: 700
    - require:
      - user: {{ username }}_user

{{ username }}_authorized_keys:
  file.managed:
    - name: /home/{{ username }}/.ssh/authorized_keys
    - user: {{ username }}
    - group: {{ username }}
    - mode: 600
    - contents: |
        {% for key in user_data.get('ssh_keys', []) %}
        {{ key }}
        {% endfor %}
    - require:
      - file: {{ username }}_ssh_dir

{% endfor %}

# Eliminar usuarios no deseados
{% for username in pillar.get('removed_users', []) %}
{{ username }}_removed:
  user.absent:
    - name: {{ username }}
    - purge: true
{% endfor %}
