#!/bin/bash
# Script para verificar compatibilidad del servidor con Nomad
# y hacer una prueba real de funcionamiento
#
# Uso: bash check-nomad-compatibility.sh

set -uo pipefail

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
echo "  Verificación de compatibilidad Nomad"
echo "============================================"
echo ""

# 1. Verificar que es Linux
echo "Verificando sistema operativo..."
if [[ "$(uname)" == "Linux" ]]; then
    log_ok "Sistema operativo: Linux $(uname -r)"
else
    log_fail "Nomad requiere Linux, detectado: $(uname)"
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
if [[ $TOTAL_MEM_MB -ge 1024 ]]; then
    log_ok "Memoria: ${TOTAL_MEM_MB}MB (mínimo 1024MB para Nomad)"
else
    log_warn "Memoria baja: ${TOTAL_MEM_MB}MB (recomendado 1024MB+)"
    ((WARNINGS++))
fi

# 4. Verificar Docker
echo "Verificando Docker..."
if command -v docker &> /dev/null; then
    log_ok "Docker instalado: $(docker --version | head -1)"
    
    if docker ps &> /dev/null; then
        log_ok "Docker daemon accesible"
    else
        log_fail "Docker daemon no accesible (¿permisos?)"
        ((ERRORS++))
    fi
else
    log_fail "Docker no instalado - Nomad lo necesita como driver"
    ((ERRORS++))
fi

# 5. Verificar conectividad
echo "Verificando conectividad..."
if curl -sf --connect-timeout 5 https://releases.hashicorp.com > /dev/null 2>&1; then
    log_ok "Conectividad a releases.hashicorp.com"
else
    log_warn "No hay conectividad a releases.hashicorp.com"
    ((WARNINGS++))
fi

# 6. Verificar puertos típicos de Nomad
echo "Verificando puertos..."
PORTS="4646 4647 4648"
for port in $PORTS; do
    if ss -tlnp 2>/dev/null | grep -q ":$port " || netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        log_warn "Puerto $port en uso - Nomad lo necesita"
        ((WARNINGS++))
    else
        log_ok "Puerto $port: disponible"
    fi
done

# Resumen parcial
echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}Hay errores que impiden continuar.${NC}"
    exit 1
fi

echo "============================================"
echo "  Prueba de instalación de Nomad"
echo "============================================"
echo ""

# 7. Descargar Nomad temporalmente
NOMAD_VERSION="1.7.3"
NOMAD_URL="https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip"
# Usar /root o home en lugar de /tmp para evitar restricciones noexec/SELinux
TEMP_DIR="${HOME}/nomad-test-$$"
mkdir -p "$TEMP_DIR"

echo "Descargando Nomad ${NOMAD_VERSION}..."
if curl -sfL "$NOMAD_URL" -o "$TEMP_DIR/nomad.zip"; then
    log_ok "Descarga completada"
else
    log_fail "Error descargando Nomad"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Extrayendo..."
if command -v unzip &> /dev/null; then
    unzip -q "$TEMP_DIR/nomad.zip" -d "$TEMP_DIR"
    log_ok "Extracción completada"
else
    log_fail "unzip no instalado - instalar con: apt install unzip"
    rm -rf "$TEMP_DIR"
    exit 1
fi

chmod +x "$TEMP_DIR/nomad"

# 8. Verificar que el binario funciona
echo "Verificando binario..."
if "$TEMP_DIR/nomad" version &> /dev/null; then
    log_ok "Nomad binario funciona: $($TEMP_DIR/nomad version | head -1)"
else
    log_fail "Nomad binario no funciona"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 9. Iniciar Nomad en modo dev temporalmente
echo ""
echo "============================================"
echo "  Prueba de ejecución (modo dev)"
echo "============================================"
echo ""

echo "Iniciando Nomad en modo dev (5 segundos)..."
"$TEMP_DIR/nomad" agent -dev -bind=127.0.0.1 &> "$TEMP_DIR/nomad.log" &
NOMAD_PID=$!

# Esperar a que inicie
sleep 3

# Verificar si sigue corriendo
if kill -0 $NOMAD_PID 2>/dev/null; then
    log_ok "Nomad agent iniciado correctamente (PID: $NOMAD_PID)"
    
    # Intentar consultar el API
    sleep 2
    if curl -sf http://127.0.0.1:4646/v1/status/leader &> /dev/null; then
        log_ok "Nomad API responde correctamente"
        NOMAD_WORKS=true
    else
        log_warn "Nomad API no responde (puede necesitar más tiempo)"
        NOMAD_WORKS=false
    fi
    
    # Detener Nomad
    echo "Deteniendo Nomad de prueba..."
    kill $NOMAD_PID 2>/dev/null
    wait $NOMAD_PID 2>/dev/null
    log_ok "Nomad detenido"
else
    log_fail "Nomad agent falló al iniciar"
    echo "Últimas líneas del log:"
    tail -20 "$TEMP_DIR/nomad.log"
    NOMAD_WORKS=false
fi

# 10. Prueba de job con Docker (si Nomad funcionó)
if [[ "${NOMAD_WORKS:-false}" == "true" ]]; then
    echo ""
    echo "============================================"
    echo "  Prueba de job Docker"
    echo "============================================"
    echo ""
    
    # Reiniciar Nomad para la prueba de Docker
    echo "Reiniciando Nomad para prueba de Docker..."
    "$TEMP_DIR/nomad" agent -dev -bind=127.0.0.1 &> "$TEMP_DIR/nomad.log" &
    NOMAD_PID=$!
    sleep 5
    
    # Crear un job de prueba
    cat > "$TEMP_DIR/test-job.nomad" << 'EOF'
job "test-hello" {
  datacenters = ["dc1"]
  type = "batch"

  group "test" {
    task "hello" {
      driver = "docker"

      config {
        image = "alpine:latest"
        command = "echo"
        args = ["Hello from Nomad on OpenVZ!"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
EOF

    echo "Ejecutando job de prueba con Docker..."
    if "$TEMP_DIR/nomad" job run "$TEMP_DIR/test-job.nomad" &> "$TEMP_DIR/job.log"; then
        log_ok "Job enviado correctamente"
        
        # Esperar a que termine
        sleep 10
        
        # Verificar estado
        JOB_STATUS=$("$TEMP_DIR/nomad" job status test-hello 2>/dev/null | grep -A5 "Allocations" | tail -1 | awk '{print $6}')
        if [[ "$JOB_STATUS" == "complete" ]] || [[ "$JOB_STATUS" == "running" ]]; then
            log_ok "Job Docker ejecutado correctamente (status: $JOB_STATUS)"
            DOCKER_WORKS=true
        else
            log_warn "Job terminó con status: $JOB_STATUS"
            echo "Log del job:"
            "$TEMP_DIR/nomad" job status test-hello 2>/dev/null || true
            DOCKER_WORKS=false
        fi
        
        # Limpiar job
        "$TEMP_DIR/nomad" job stop -purge test-hello &> /dev/null || true
    else
        log_fail "Error al ejecutar job"
        cat "$TEMP_DIR/job.log"
        DOCKER_WORKS=false
    fi
    
    # Detener Nomad
    kill $NOMAD_PID 2>/dev/null
    wait $NOMAD_PID 2>/dev/null
fi

# Limpiar
rm -rf "$TEMP_DIR"

# Resumen final
echo ""
echo "============================================"
echo "                 RESUMEN"
echo "============================================"
echo ""

if [[ "${NOMAD_WORKS:-false}" == "true" ]] && [[ "${DOCKER_WORKS:-false}" == "true" ]]; then
    echo -e "${GREEN}✓ Nomad funciona correctamente en este servidor${NC}"
    echo ""
    echo "Nomad puede:"
    echo "  ✓ Ejecutar como agent"
    echo "  ✓ Usar Docker como driver"
    echo "  ✓ Correr containers"
    echo ""
    echo "Próximo paso: instalar Nomad permanentemente"
    exit 0
elif [[ "${NOMAD_WORKS:-false}" == "true" ]]; then
    echo -e "${YELLOW}⚠ Nomad funciona pero Docker driver tiene problemas${NC}"
    echo ""
    echo "Revisar configuración de Docker."
    exit 1
else
    echo -e "${RED}✗ Nomad no funciona en este servidor${NC}"
    echo ""
    echo "Revisar los errores anteriores."
    exit 1
fi
