#!/bin/bash
# Script para verificar compatibilidad del servidor con K3s
# Ejecutar en el servidor ANTES de instalar K3s
#
# Uso: curl -fsSL https://raw.githubusercontent.com/cyberplant/gdu_infra/main/scripts/check-k3s-compatibility.sh | bash

set -uo pipefail
# Nota: no usamos -e porque ((var++)) retorna 1 cuando var=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

ERRORS=0
WARNINGS=0

echo "============================================"
echo "  Verificación de compatibilidad K3s"
echo "============================================"
echo ""

# 1. Verificar que es Linux
echo "Verificando sistema operativo..."
if [[ "$(uname)" == "Linux" ]]; then
    log_ok "Sistema operativo: Linux $(uname -r)"
else
    log_fail "K3s requiere Linux, detectado: $(uname)"
    ((ERRORS++))
fi

# 2. Verificar arquitectura
ARCH=$(uname -m)
echo "Verificando arquitectura..."
if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    log_ok "Arquitectura soportada: $ARCH"
else
    log_fail "Arquitectura no soportada: $ARCH"
    ((ERRORS++))
fi

# 3. Verificar memoria
echo "Verificando memoria..."
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
if [[ $TOTAL_MEM_MB -ge 2048 ]]; then
    log_ok "Memoria: ${TOTAL_MEM_MB}MB (mínimo 2048MB)"
else
    log_fail "Memoria insuficiente: ${TOTAL_MEM_MB}MB (mínimo 2048MB)"
    ((ERRORS++))
fi

# 4. Verificar CPU
echo "Verificando CPUs..."
CPU_COUNT=$(nproc)
if [[ $CPU_COUNT -ge 2 ]]; then
    log_ok "CPUs: $CPU_COUNT (mínimo 2)"
else
    log_warn "CPUs: $CPU_COUNT (recomendado 2+)"
    ((WARNINGS++))
fi

# 5. Verificar espacio en disco
echo "Verificando espacio en disco..."
ROOT_FREE_KB=$(df / | tail -1 | awk '{print $4}')
ROOT_FREE_GB=$((ROOT_FREE_KB / 1024 / 1024))
if [[ $ROOT_FREE_GB -ge 20 ]]; then
    log_ok "Espacio libre en /: ${ROOT_FREE_GB}GB (mínimo 20GB)"
else
    log_warn "Espacio libre en /: ${ROOT_FREE_GB}GB (recomendado 20GB+)"
    ((WARNINGS++))
fi

# 6. Verificar si es root o tiene sudo
echo "Verificando permisos..."
if [[ $EUID -eq 0 ]]; then
    log_ok "Ejecutando como root"
elif command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
    log_ok "Tiene acceso sudo sin password"
elif command -v sudo &> /dev/null; then
    log_ok "Tiene sudo (requiere password)"
else
    log_fail "No tiene acceso root ni sudo"
    ((ERRORS++))
fi

# 7. Verificar módulos del kernel necesarios
echo "Verificando módulos del kernel..."
REQUIRED_MODULES="br_netfilter overlay"
for mod in $REQUIRED_MODULES; do
    if lsmod | grep -q "^$mod" || [[ -d "/sys/module/$mod" ]]; then
        log_ok "Módulo $mod: cargado"
    else
        # Intentar cargar
        if modprobe $mod 2>/dev/null; then
            log_ok "Módulo $mod: cargado (recién)"
        else
            log_warn "Módulo $mod: no disponible (K3s intentará cargarlo)"
            ((WARNINGS++))
        fi
    fi
done

# 8. Verificar cgroups v2 o v1
echo "Verificando cgroups..."
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    log_ok "cgroups v2 detectado"
elif [[ -d /sys/fs/cgroup/memory ]]; then
    log_ok "cgroups v1 detectado"
else
    log_warn "No se pudo determinar versión de cgroups"
    ((WARNINGS++))
fi

# 9. Verificar iptables
echo "Verificando iptables..."
if command -v iptables &> /dev/null; then
    log_ok "iptables disponible"
else
    log_warn "iptables no encontrado (K3s lo necesita)"
    ((WARNINGS++))
fi

# 10. Verificar si hay Docker corriendo (puede interferir)
echo "Verificando Docker..."
if systemctl is-active --quiet docker 2>/dev/null; then
    log_warn "Docker está corriendo - K3s usa containerd, pueden coexistir pero verificar"
    ((WARNINGS++))
elif command -v docker &> /dev/null; then
    log_ok "Docker instalado pero no corriendo"
else
    log_ok "Docker no instalado (OK, K3s usa containerd)"
fi

# 11. Verificar puertos
echo "Verificando puertos..."
PORTS="6443 10250 80 443"
for port in $PORTS; do
    if ss -tlnp 2>/dev/null | grep -q ":$port " || netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        log_warn "Puerto $port en uso - puede haber conflicto"
        ((WARNINGS++))
    else
        log_ok "Puerto $port: disponible"
    fi
done

# 12. Verificar conectividad
echo "Verificando conectividad..."
if curl -sf --connect-timeout 5 https://get.k3s.io > /dev/null 2>&1; then
    log_ok "Conectividad a get.k3s.io"
else
    log_fail "No hay conectividad a get.k3s.io"
    ((ERRORS++))
fi

if curl -sf --connect-timeout 5 https://ghcr.io > /dev/null 2>&1; then
    log_ok "Conectividad a ghcr.io (registry)"
else
    log_warn "No hay conectividad a ghcr.io"
    ((WARNINGS++))
fi

# 13. Verificar si es un VPS/VM o contenedor
echo "Verificando tipo de virtualización..."
if [[ -f /proc/1/cgroup ]]; then
    if grep -q docker /proc/1/cgroup 2>/dev/null || grep -q lxc /proc/1/cgroup 2>/dev/null; then
        log_warn "Parece ser un contenedor - K3s puede no funcionar correctamente"
        ((WARNINGS++))
    else
        log_ok "No es un contenedor"
    fi
fi

if command -v systemd-detect-virt &> /dev/null; then
    VIRT=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    if [[ "$VIRT" == "openvz" ]] || [[ "$VIRT" == "lxc" ]]; then
        log_fail "Virtualización $VIRT detectada - K3s NO funciona en OpenVZ/LXC"
        ((ERRORS++))
    elif [[ "$VIRT" != "none" ]] && [[ "$VIRT" != "unknown" ]]; then
        log_ok "Virtualización: $VIRT (compatible)"
    else
        log_ok "Servidor físico o VM compatible"
    fi
fi

# Resumen
echo ""
echo "============================================"
echo "                 RESUMEN"
echo "============================================"

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ Todo OK - El servidor es compatible con K3s${NC}"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Compatible con advertencias${NC}"
    echo "  Errores: 0"
    echo "  Advertencias: $WARNINGS"
    echo ""
    echo "K3s debería funcionar, pero revisa las advertencias."
    exit 0
else
    echo -e "${RED}✗ Hay problemas de compatibilidad${NC}"
    echo "  Errores: $ERRORS"
    echo "  Advertencias: $WARNINGS"
    echo ""
    echo "Revisa los errores antes de instalar K3s."
    exit 1
fi
