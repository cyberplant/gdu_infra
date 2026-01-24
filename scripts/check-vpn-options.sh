#!/bin/bash
# Script para diagnosticar opciones de VPN disponibles en OpenVZ
# Ejecutar en el servidor: bash check-vpn-options.sh

set -e

echo "=============================================="
echo "  Diagnóstico de VPN para OpenVZ"
echo "=============================================="
echo ""

# Detectar virtualización
echo "## Tipo de virtualización"
if [ -f /proc/user_beancounters ]; then
    echo "✓ OpenVZ detectado"
    OPENVZ=true
else
    echo "✗ No es OpenVZ (o es OpenVZ 7+/Virtuozzo)"
    OPENVZ=false
fi

if command -v systemd-detect-virt &> /dev/null; then
    echo "  systemd-detect-virt: $(systemd-detect-virt 2>/dev/null || echo 'N/A')"
fi
echo ""

# Verificar /dev/net/tun (necesario para OpenVPN y WireGuard userspace)
echo "## Dispositivo TUN/TAP"
if [ -c /dev/net/tun ]; then
    echo "✓ /dev/net/tun disponible (OpenVPN/Tailscale posible)"
    TUN_OK=true
else
    echo "✗ /dev/net/tun NO disponible"
    echo "  Contactar al proveedor para habilitar TUN/TAP"
    TUN_OK=false
fi
echo ""

# Verificar módulos de kernel (WireGuard nativo)
echo "## Módulo WireGuard (kernel)"
if lsmod 2>/dev/null | grep -q wireguard; then
    echo "✓ Módulo wireguard cargado"
    WG_KERNEL=true
elif modprobe wireguard 2>/dev/null; then
    echo "✓ Módulo wireguard disponible (se pudo cargar)"
    WG_KERNEL=true
else
    echo "✗ WireGuard kernel NO disponible (normal en OpenVZ)"
    WG_KERNEL=false
fi
echo ""

# Verificar herramientas instaladas
echo "## Software instalado"

check_installed() {
    if command -v "$1" &> /dev/null; then
        echo "✓ $1 instalado: $(command -v $1)"
        return 0
    else
        echo "✗ $1 no instalado"
        return 1
    fi
}

check_installed tailscale && TAILSCALE=true || TAILSCALE=false
check_installed zerotier-cli && ZEROTIER=true || ZEROTIER=false
check_installed openvpn && OPENVPN=true || OPENVPN=false
check_installed wg && WG_TOOLS=true || WG_TOOLS=false
check_installed cloudflared && CLOUDFLARED=true || CLOUDFLARED=false
echo ""

# Verificar conectividad de puertos
echo "## Puertos de red"
echo "  Verificando puertos típicos de VPN..."

check_port() {
    if timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/$1" 2>/dev/null; then
        echo "  Puerto $1: EN USO"
    else
        echo "  Puerto $1: disponible"
    fi
}

check_port 51820  # WireGuard
check_port 1194   # OpenVPN
check_port 9993   # ZeroTier
check_port 41641  # Tailscale
echo ""

# Test de conectividad saliente
echo "## Conectividad saliente (UDP)"
if timeout 3 nc -zu 8.8.8.8 53 2>/dev/null; then
    echo "✓ UDP saliente funciona (DNS test)"
    UDP_OUT=true
else
    echo "? UDP saliente - no se pudo verificar (puede funcionar igual)"
    UDP_OUT=unknown
fi
echo ""

# Resumen y recomendaciones
echo "=============================================="
echo "  RESUMEN Y RECOMENDACIONES"
echo "=============================================="
echo ""

RECOMMENDATIONS=""

if [ "$TUN_OK" = true ]; then
    echo "### Opción 1: Tailscale (RECOMENDADO)"
    echo "  - Usa WireGuard en userspace"
    echo "  - Maneja IP dinámica automáticamente"
    echo "  - Fácil de configurar"
    echo "  - Instalación:"
    echo "    curl -fsSL https://tailscale.com/install.sh | sh"
    echo "    tailscale up"
    echo ""
    RECOMMENDATIONS="tailscale"
    
    echo "### Opción 2: ZeroTier"
    echo "  - Similar a Tailscale"
    echo "  - También maneja IP dinámica"
    echo "  - Instalación:"
    echo "    curl -s https://install.zerotier.com | sudo bash"
    echo "    zerotier-cli join <network-id>"
    echo ""
    
    echo "### Opción 3: OpenVPN"
    echo "  - Más complejo de configurar"
    echo "  - Requiere gestión de certificados"
    echo "  - El servidor debe tener IP fija (tu VPS)"
    echo ""
fi

if [ "$TUN_OK" = false ]; then
    echo "### Opción alternativa: SSH Tunnel (siempre funciona)"
    echo "  - No requiere /dev/net/tun"
    echo "  - Desde casa hacia el servidor:"
    echo "    ssh -N -R 4646:localhost:4646 -R 4647:localhost:4647 user@servidor"
    echo "  - Usar autossh para reconexión automática"
    echo ""
    
    echo "### Opción alternativa: Cloudflare Tunnel"
    echo "  - No requiere /dev/net/tun"
    echo "  - No requiere puertos abiertos"
    echo "  - Solo para tráfico HTTP/TCP específico"
    echo ""
fi

echo "### Solución para IP dinámica en casa"
echo "  La clave es que la conexión se INICIE desde casa:"
echo "  - Tailscale/ZeroTier: manejan esto automáticamente"
echo "  - WireGuard manual: usar PersistentKeepalive=25"
echo "  - MikroTik: configurar como cliente, no servidor"
echo ""

echo "=============================================="
echo "  Para copiar este resultado:"
echo "  bash check-vpn-options.sh 2>&1 | tee vpn-diagnostic.txt"
echo "=============================================="
