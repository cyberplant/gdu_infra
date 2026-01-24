#!/bin/bash
# Bootstrap script para servidor GDU con Nomad
# Ejecutar como root en un servidor Debian/Ubuntu
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/cyberplant/gdu_infra/main/scripts/bootstrap.sh | sudo bash
#
# O manualmente:
#   sudo bash bootstrap.sh

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Trap para mostrar línea de error
trap 'log_error "Error en línea $LINENO. Comando: $BASH_COMMAND"' ERR

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
# 2. Instalar Salt minion via pip
# ============================================
log_info "Instalando Salt..."

if ! command -v salt-call &> /dev/null; then
    if [[ "$OS" == "debian" ]]; then
        # Instalar dependencias de Python para Salt
        apt-get install -y python3 python3-pip python3-venv
        
        # Instalar Salt 3006 via pip (compatible con Python 3.8)
        log_info "Instalando Salt 3006 via pip..."
        pip3 install --break-system-packages 'salt==3006.9' || pip3 install 'salt==3006.9'
        
        # Crear directorios necesarios
        mkdir -p /etc/salt/minion.d
        mkdir -p /var/cache/salt
        mkdir -p /var/log/salt
    fi
else
    log_info "Salt ya está instalado"
fi

# Verificar que Salt se instaló correctamente
if ! command -v salt-call &> /dev/null; then
    log_error "Salt no se instaló correctamente"
    exit 1
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

# Agregar /usr/local/bin al PATH para este script
export PATH=$PATH:/usr/local/bin

# ============================================
# 6. Configurar secrets de Nomad
# ============================================
log_info "Configurando secrets..."

# Esperar a que Nomad esté listo
log_info "Esperando a que Nomad esté listo..."
for i in {1..30}; do
    if nomad status &>/dev/null; then
        break
    fi
    sleep 2
done

# Generar passwords random si no existen
SECRETS_FILE="/root/.gdu_secrets"
if [[ ! -f "$SECRETS_FILE" ]]; then
    log_info "Generando passwords random..."
    
    POSTGRES_ROOT_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    GDU_USUARIOS_DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    GDU_PORTAL_PROVEEDORES_DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    DJANGO_SECRET_USUARIOS=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | head -c 50)
    DJANGO_SECRET_PROVEEDORES=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | head -c 50)
    GRAFANA_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    # Guardar en archivo (solo root puede leer)
    cat > "$SECRETS_FILE" <<EOF
POSTGRES_ROOT_PASS=$POSTGRES_ROOT_PASS
GDU_USUARIOS_DB_PASS=$GDU_USUARIOS_DB_PASS
GDU_PORTAL_PROVEEDORES_DB_PASS=$GDU_PORTAL_PROVEEDORES_DB_PASS
DJANGO_SECRET_USUARIOS=$DJANGO_SECRET_USUARIOS
DJANGO_SECRET_PROVEEDORES=$DJANGO_SECRET_PROVEEDORES
GRAFANA_PASS=$GRAFANA_PASS
EOF
    chmod 600 "$SECRETS_FILE"
else
    log_info "Cargando secrets existentes de $SECRETS_FILE"
    source "$SECRETS_FILE"
fi

# Siempre asegurar que las variables de Nomad existan
log_info "Configurando secrets en Nomad Variables..."

nomad var put nomad/jobs/postgres \
    postgres_password="$POSTGRES_ROOT_PASS" \
    gdu_usuarios_password="$GDU_USUARIOS_DB_PASS" \
    gdu_proveedores_password="$GDU_PORTAL_PROVEEDORES_DB_PASS"

nomad var put nomad/jobs/gdu-usuarios \
    db_password="$GDU_USUARIOS_DB_PASS" \
    django_secret_key="$DJANGO_SECRET_USUARIOS"

nomad var put nomad/jobs/gdu-portal-proveedores \
    db_password="$GDU_PORTAL_PROVEEDORES_DB_PASS" \
    django_secret_key="$DJANGO_SECRET_PROVEEDORES"

nomad var put nomad/jobs/monitoring \
    grafana_admin_password="$GRAFANA_PASS"

log_info "Secrets configurados en Nomad Variables"

# Login a ghcr.io si hay token
if [[ -n "${GHCR_TOKEN:-}" ]]; then
    log_info "Configurando acceso a ghcr.io..."
    echo "$GHCR_TOKEN" | docker login ghcr.io -u cyberplant --password-stdin
fi

# ============================================
# 7. Desplegar PostgreSQL
# ============================================
log_info "Desplegando PostgreSQL..."
nomad job run /srv/gdu_infra/nomad/postgres.nomad

# ============================================
# 8. Inicializar bases de datos con Salt
# ============================================
log_info "Inicializando bases de datos..."
salt-call --local state.apply nomad.postgres-init

# ============================================
# 9. Desplegar resto de jobs de Nomad
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
echo "  1. Login a ghcr.io:"
echo "     echo 'TOKEN' | docker login ghcr.io -u cyberplant --password-stdin"
echo ""
echo "  2. Re-desplegar jobs si es necesario:"
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
