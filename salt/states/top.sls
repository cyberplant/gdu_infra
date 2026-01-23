base:
  '*':
    - base.packages
    - base.timezone
    - base.users
    - base.ssh
    - base.firewall
    - nomad.install
    - nomad.jobs
