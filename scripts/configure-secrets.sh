#!/bin/bash
# Script interactivo para configurar secrets en Nomad Variables
# Los secrets NO se guardan en el repositorio, solo en Nomad
# Uso: ./configure-secrets.sh [job-name]
# Ejemplo: ./configure-secrets.sh gdu-portal-proveedores

set -e

NOMAD_BIN="${NOMAD_BIN:-/usr/local/bin/nomad}"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=============================================="
echo "  Configuración de Secrets para Nomad"
echo -e "==============================================${NC}"
echo ""

# Verificar que Nomad está disponible
if ! command -v $NOMAD_BIN &> /dev/null; then
    echo -e "${RED}Error: nomad no encontrado en $NOMAD_BIN${NC}"
    exit 1
fi

# Función para leer input con valor por defecto
read_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local is_secret="$4"
    
    if [ -n "$default" ]; then
        prompt="$prompt [$default]"
    fi
    
    if [ "$is_secret" = "true" ]; then
        read -sp "$prompt: " value
        echo ""
    else
        read -p "$prompt: " value
    fi
    
    if [ -z "$value" ] && [ -n "$default" ]; then
        value="$default"
    fi
    
    eval "$var_name='$value'"
}

# Función para obtener valor actual de Nomad Variable
get_current_value() {
    local var_path="$1"
    local key="$2"
    $NOMAD_BIN var get -out=json "$var_path" 2>/dev/null | jq -r ".Items.$key // empty" 2>/dev/null || echo ""
}

configure_gdu_usuarios() {
    echo -e "${YELLOW}Configurando: nomad/jobs/gdu-usuarios${NC}"
    echo ""
    
    local var_path="nomad/jobs/gdu-usuarios"
    
    # Obtener valores actuales
    local current_db_pass=$(get_current_value "$var_path" "db_password")
    local current_secret_key=$(get_current_value "$var_path" "django_secret_key")
    
    read_with_default "DB Password" "$current_db_pass" db_password true
    read_with_default "Django Secret Key" "$current_secret_key" django_secret_key true
    
    echo ""
    echo "Guardando en Nomad..."
    $NOMAD_BIN var put -force "$var_path" \
        db_password="$db_password" \
        django_secret_key="$django_secret_key"
    
    echo -e "${GREEN}✓ gdu-usuarios configurado${NC}"
}

configure_gdu_portal_proveedores() {
    echo -e "${YELLOW}Configurando: nomad/jobs/gdu-portal-proveedores${NC}"
    echo ""
    
    local var_path="nomad/jobs/gdu-portal-proveedores"
    
    # Obtener valores actuales
    local current_db_pass=$(get_current_value "$var_path" "db_password")
    local current_secret_key=$(get_current_value "$var_path" "django_secret_key")
    local current_oauth_id=$(get_current_value "$var_path" "oauth_client_id")
    local current_oauth_secret=$(get_current_value "$var_path" "oauth_client_secret")
    
    read_with_default "DB Password" "$current_db_pass" db_password true
    read_with_default "Django Secret Key" "$current_secret_key" django_secret_key true
    
    echo ""
    echo -e "${YELLOW}OAuth2 (de gdu-usuarios admin -> OAuth2 Provider -> Applications)${NC}"
    read_with_default "OAuth2 Client ID" "$current_oauth_id" oauth_client_id false
    read_with_default "OAuth2 Client Secret" "$current_oauth_secret" oauth_client_secret true
    
    echo ""
    echo "Guardando en Nomad..."
    $NOMAD_BIN var put -force "$var_path" \
        db_password="$db_password" \
        django_secret_key="$django_secret_key" \
        oauth_client_id="$oauth_client_id" \
        oauth_client_secret="$oauth_client_secret"
    
    echo -e "${GREEN}✓ gdu-portal-proveedores configurado${NC}"
}

configure_postgres() {
    echo -e "${YELLOW}Configurando: nomad/jobs/postgres${NC}"
    echo ""
    
    local var_path="nomad/jobs/postgres"
    
    # Obtener valores actuales
    local current_root_pass=$(get_current_value "$var_path" "postgres_password")
    local current_usuarios_pass=$(get_current_value "$var_path" "gdu_usuarios_password")
    local current_proveedores_pass=$(get_current_value "$var_path" "gdu_portal_proveedores_password")
    
    read_with_default "PostgreSQL Root Password" "$current_root_pass" postgres_password true
    read_with_default "gdu_usuarios DB Password" "$current_usuarios_pass" gdu_usuarios_password true
    read_with_default "gdu_portal_proveedores DB Password" "$current_proveedores_pass" gdu_portal_proveedores_password true
    
    echo ""
    echo "Guardando en Nomad..."
    $NOMAD_BIN var put -force "$var_path" \
        postgres_password="$postgres_password" \
        gdu_usuarios_password="$gdu_usuarios_password" \
        gdu_portal_proveedores_password="$gdu_portal_proveedores_password"
    
    echo -e "${GREEN}✓ postgres configurado${NC}"
}

show_current_vars() {
    echo -e "${YELLOW}Variables actuales en Nomad:${NC}"
    echo ""
    
    for var_path in "nomad/jobs/postgres" "nomad/jobs/gdu-usuarios" "nomad/jobs/gdu-portal-proveedores"; do
        echo -e "${GREEN}$var_path:${NC}"
        if $NOMAD_BIN var get -out=json "$var_path" 2>/dev/null | jq -r '.Items | keys[]' 2>/dev/null; then
            echo ""
        else
            echo "  (no configurado)"
            echo ""
        fi
    done
}

# Menú principal
case "${1:-menu}" in
    gdu-usuarios)
        configure_gdu_usuarios
        ;;
    gdu-portal-proveedores)
        configure_gdu_portal_proveedores
        ;;
    postgres)
        configure_postgres
        ;;
    all)
        configure_postgres
        echo ""
        configure_gdu_usuarios
        echo ""
        configure_gdu_portal_proveedores
        ;;
    list|show)
        show_current_vars
        ;;
    menu|*)
        echo "Uso: $0 [comando]"
        echo ""
        echo "Comandos:"
        echo "  postgres                 - Configurar secrets de PostgreSQL"
        echo "  gdu-usuarios             - Configurar secrets de gdu-usuarios"
        echo "  gdu-portal-proveedores   - Configurar secrets de gdu-portal-proveedores"
        echo "  all                      - Configurar todos los secrets"
        echo "  list                     - Mostrar variables configuradas"
        echo ""
        echo "Ejemplo:"
        echo "  $0 gdu-portal-proveedores"
        ;;
esac
