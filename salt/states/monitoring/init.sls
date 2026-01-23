# Despliegue del stack de monitoreo en K3s
deploy_monitoring:
  cmd.run:
    - name: |
        kubectl apply -k /srv/gdu_infra/k8s/monitoring/
    - require:
      - sls: k3s.install
    - unless: kubectl get deployment prometheus -n monitoring 2>/dev/null

wait_monitoring_ready:
  cmd.run:
    - name: |
        kubectl wait --for=condition=available deployment/prometheus -n monitoring --timeout=300s
        kubectl wait --for=condition=available deployment/grafana -n monitoring --timeout=300s
    - require:
      - cmd: deploy_monitoring
