#!/bin/bash
# Script wrapper para deploy de aplicaciones
# Uso: ./deploy.sh [app-name|all]
# Ejemplos:
#   ./deploy.sh gdu-usuarios
#   ./deploy.sh gdu-portal-proveedores
#   ./deploy.sh all

set -e

APP="${1:-all}"

if [ "$APP" = "-h" ] || [ "$APP" = "--help" ]; then
    echo "Uso: $0 [app-name|all]"
    echo ""
    echo "Apps disponibles:"
    echo "  gdu-usuarios"
    echo "  gdu-portal-proveedores"
    echo "  all (deploy todas)"
    exit 0
fi

echo "=============================================="
echo "  Deploy de: $APP"
echo "=============================================="
echo ""

# Ejecutar estado Salt
salt-call --local state.apply nomad.deploy pillar="{\"app\": \"$APP\"}"

echo ""
echo "=============================================="
echo "  Deploy completado"
echo "=============================================="
