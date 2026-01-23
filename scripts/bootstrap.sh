#!/bin/bash
# Bootstrap script para servidor GDU con Nomad
# Ejecutar como root en un servidor Debian/Ubuntu
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/cyberplant/gdu_infra/main/scripts/bootstrap.sh | sudo bash
#
# O manualmente:
#   sudo bash bootstrap.sh

set -uo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificar que se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
fi

# Detectar sistema operativo
if [[ -f /etc/debian_version ]]; then
    OS="debian"
elif [[ -f /etc/redhat-release ]]; then
    OS="rhel"
else
    log_error "Sistema operativo no soportado"
    exit 1
fi

log_info "Sistema detectado: $OS"
log_info "Iniciando bootstrap del servidor GDU con Nomad..."

# ============================================
# 1. Actualizar sistema e instalar dependencias
# ============================================
log_info "Actualizando sistema..."

if [[ "$OS" == "debian" ]]; then
    apt-get update
    apt-get upgrade -y
    apt-get install -y \
        curl \
        wget \
        git \
        vim \
        htop \
        jq \
        net-tools \
        unzip \
        gnupg \
        apt-transport-https \
        ca-certificates \
        software-properties-common
fi

# ============================================
# 2. Instalar Salt minion
# ============================================
log_info "Instalando Salt..."

if ! command -v salt-call &> /dev/null; then
    if [[ "$OS" == "debian" ]]; then
        # Instalar Salt desde repo oficial
        curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public | gpg --dearmor -o /etc/apt/keyrings/salt-archive-keyring.gpg
        
        # Detectar versión de Debian/Ubuntu
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            CODENAME=$VERSION_CODENAME
        fi
        
        echo "deb [signed-by=/etc/apt/keyrings/salt-archive-keyring.gpg] https://packages.broadcom.com/artifactory/saltproject-deb stable main" > /etc/apt/sources.list.d/salt.list
        
        apt-get update
        apt-get install -y salt-minion
    fi
    
    # Deshabilitar servicio salt-minion (usamos masterless)
    systemctl stop salt-minion || true
    systemctl disable salt-minion || true
else
    log_info "Salt ya está instalado"
fi

# ============================================
# 3. Clonar repositorio de infraestructura
# ============================================
log_info "Clonando repositorio gdu_infra..."

GDU_INFRA_PATH="/srv/gdu_infra"

if [[ -d "$GDU_INFRA_PATH" ]]; then
    log_info "Repositorio ya existe, actualizando..."
    cd "$GDU_INFRA_PATH"
    git pull origin main || true
else
    git clone https://github.com/cyberplant/gdu_infra.git "$GDU_INFRA_PATH"
fi

# ============================================
# 4. Configurar Salt masterless
# ============================================
log_info "Configurando Salt en modo masterless..."

mkdir -p /etc/salt/minion.d
cp "$GDU_INFRA_PATH/salt/minion.conf" /etc/salt/minion.d/local.conf

# Crear directorio de logs
mkdir -p /var/log/salt

# ============================================
# 5. Ejecutar estados Salt
# ============================================
log_info "Aplicando configuración Salt..."

# Primero aplicar estados base
salt-call --local state.apply base.packages
salt-call --local state.apply base.timezone
salt-call --local state.apply base.users
salt-call --local state.apply base.ssh
salt-call --local state.apply base.firewall

# Instalar Nomad
log_info "Instalando Nomad..."
salt-call --local state.apply nomad.install

# ============================================
# 6. Configurar secrets de Nomad
# ============================================
log_info "Configurando secrets..."

# Verificar si hay secrets configurados
if [[ ! -f /srv/gdu_infra/salt/pillar/secrets.sls ]]; then
    log_warn "No se encontró secrets.sls - los jobs usarán passwords por defecto"
    log_warn "Crear /srv/gdu_infra/salt/pillar/secrets.sls antes de producción"
fi

# Login a ghcr.io si hay token
if [[ -n "${GHCR_TOKEN:-}" ]]; then
    log_info "Configurando acceso a ghcr.io..."
    echo "$GHCR_TOKEN" | docker login ghcr.io -u cyberplant --password-stdin
fi

# ============================================
# 7. Desplegar jobs de Nomad
# ============================================
log_info "Desplegando jobs de Nomad..."
salt-call --local state.apply nomad.jobs

# ============================================
# 8. Verificación final
# ============================================
log_info "Verificando instalación..."

echo ""
echo "============================================"
echo "          Estado de Nomad"
echo "============================================"
nomad server members || true
echo ""
echo "============================================"
echo "              Jobs en ejecución"
echo "============================================"
nomad job status || true
echo ""

# ============================================
# Resumen
# ============================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}       Bootstrap completado!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Próximos pasos:"
echo "  1. Configurar secrets de Nomad:"
echo "     nomad var put nomad/jobs/postgres postgres_password=TU_PASSWORD"
echo "     nomad var put nomad/jobs/gdu-usuarios db_password=X django_secret_key=Y"
echo "     nomad var put nomad/jobs/gdu-portal-proveedores db_password=X django_secret_key=Y"
echo ""
echo "  2. Login a ghcr.io (si no se hizo):"
echo "     echo 'TOKEN' | docker login ghcr.io -u cyberplant --password-stdin"
echo ""
echo "  3. Re-desplegar jobs si es necesario:"
echo "     nomad job run /srv/gdu_infra/nomad/NOMBRE.nomad"
echo ""
echo "Dominios configurados:"
echo "  - usuarios.portalgdu.com.uy     -> gdu-usuarios"
echo "  - auth.portalgdu.com.uy         -> gdu-usuarios (OAuth)"
echo "  - proveedores.gdu.uy            -> gdu-portal-proveedores"
echo "  - proveedores.portalgdu.com.uy  -> gdu-portal-proveedores"
echo "  - grafana.portalgdu.com.uy      -> Grafana (monitoreo)"
echo ""
echo "Comandos útiles:"
echo "  nomad job status                       # Ver jobs"
echo "  nomad alloc logs -f ALLOC_ID           # Ver logs"
echo "  nomad job restart JOB_NAME             # Reiniciar job"
echo "  salt-call --local state.apply          # Re-aplicar configuración Salt"
echo ""
