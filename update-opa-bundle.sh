#!/bin/bash

# ==============================================================================
# Script de Atualização de Bundle OPA via GitHub + SeaweedFS S3
# Uso: ./update-opa-bundle.sh <github-repo-url> [branch]
#
# Exemplos:
#   ./update-opa-bundle.sh https://github.com/usuario/opa-policies.git
#   ./update-opa-bundle.sh https://github.com/usuario/opa-policies.git main
#   ./update-opa-bundle.sh https://github.com/usuario/opa-policies.git develop
#
# Fluxo:
#   GitHub → Clone → Validação → Bundle → Upload S3 → OPA (download via Filer)
# ==============================================================================

set -e

# ==============================================================================
# CONFIGURAÇÕES (ajuste via variáveis de ambiente se necessário)
# ==============================================================================

# SeaweedFS S3 Gateway (para upload do bundle)
S3_ENDPOINT="${S3_ENDPOINT:-http://127.0.0.1:8333}"
S3_BUCKET="${S3_BUCKET:-opa-policies}"
S3_KEY="${S3_KEY:-portal-bundle.tar.gz}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-admin}"
S3_SECRET_KEY="${S3_SECRET_KEY:-admin_secret}"

# SeaweedFS Filer (para verificação pós-upload)
FILER_URL="${FILER_URL:-http://127.0.0.1:8888}"

# Diretório temporário de trabalho
WORK_DIR="/tmp/opa-bundle-update"
BUNDLE_NAME="portal-bundle.tar.gz"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================================================
# FUNÇÕES AUXILIARES
# ==============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

cleanup() {
    log_info "Limpando diretório temporário..."
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ==============================================================================
# VALIDAÇÃO DE PARÂMETROS
# ==============================================================================
if [ $# -lt 1 ]; then
    log_error "Uso: $0 <github-repo-url> [branch]"
    echo ""
    echo "Exemplos:"
    echo "  $0 https://github.com/usuario/opa-policies.git"
    echo "  $0 https://github.com/usuario/opa-policies.git main"
    echo "  $0 https://github.com/usuario/opa-policies.git develop"
    exit 1
fi

REPO_URL="$1"
BRANCH="${2:-main}"

log_info "Repositório: $REPO_URL"
log_info "Branch:      $BRANCH"
log_info "S3 Endpoint: $S3_ENDPOINT"
log_info "S3 Bucket:   $S3_BUCKET"

# ==============================================================================
# PASSO 0: VALIDAR CONECTIVIDADE COM SEAWEEDFS S3
# ==============================================================================
log_info "Passo 0/6: Validando conectividade com SeaweedFS S3..."

S3_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${S3_ENDPOINT}/" 2>/dev/null || echo "000")

if [ "$S3_STATUS" == "000" ]; then
    log_error "SeaweedFS S3 Gateway não está acessível em ${S3_ENDPOINT}"
    log_info "Verifique se o serviço está rodando:"
    echo "   sudo systemctl status seaweedfs-s3"
    exit 1
fi

log_success "SeaweedFS S3 Gateway acessível (HTTP ${S3_STATUS})"

# ==============================================================================
# PASSO 1: CLONAR REPOSITÓRIO
# ==============================================================================
log_info "Passo 1/6: Clonando repositório..."

if ! command -v git &> /dev/null; then
    log_error "git não encontrado. Instale com: sudo apt-get install git"
    exit 1
fi

# Limpar diretório de trabalho (garantir estado limpo)
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK_DIR/repo"; then
    log_error "Falha ao clonar repositório. Verifique a URL e a branch."
    exit 1
fi

COMMIT_HASH=$(git -C "$WORK_DIR/repo" rev-parse --short HEAD)
log_success "Repositório clonado (commit: $COMMIT_HASH)"

# ==============================================================================
# PASSO 2: VALIDAR ESTRUTURA DO REPOSITÓRIO
# ==============================================================================
log_info "Passo 2/6: Validando estrutura do repositório..."

if [ ! -d "$WORK_DIR/repo/policies" ]; then
    log_error "Estrutura inválida: pasta 'policies/' não encontrada no repositório"
    log_info "Estrutura esperada:"
    echo "  repo/"
    echo "  └── policies/"
    echo "      └── *.rego"
    exit 1
fi

REGO_COUNT=$(find "$WORK_DIR/repo/policies" -name '*.rego' | wc -l)
if [ "$REGO_COUNT" -eq 0 ]; then
    log_error "Nenhum arquivo .rego encontrado em policies/"
    exit 1
fi

log_success "Estrutura validada ($REGO_COUNT arquivo(s) .rego)"

# ==============================================================================
# PASSO 3: VALIDAR SINTAXE REGO
# ==============================================================================
log_info "Passo 3/6: Validando sintaxe Rego..."

if command -v opa &> /dev/null; then
    if ! opa check "$WORK_DIR/repo/policies/"; then
        log_error "Erro de sintaxe nos arquivos Rego"
        exit 1
    fi
    log_success "Sintaxe Rego válida"
else
    log_warn "OPA não encontrado localmente, pulando validação de sintaxe"
fi

# ==============================================================================
# PASSO 4: GERAR MANIFEST
# ==============================================================================
log_info "Passo 4/6: Gerando .manifest..."

VERSION="v1-$(date +%Y%m%d-%H%M%S)"

cat > "$WORK_DIR/repo/.manifest" << EOF
{
  "revision": "$VERSION-$COMMIT_HASH",
  "roots": ["portal"],
  "metadata": {
    "repository": "$REPO_URL",
    "branch": "$BRANCH",
    "commit": "$COMMIT_HASH",
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "generated_by": "update-opa-bundle.sh"
  }
}
EOF

log_success "Manifest gerado: $VERSION-$COMMIT_HASH"

# ==============================================================================
# PASSO 5: COMPACTAR BUNDLE
# ==============================================================================
log_info "Passo 5/6: Compactando bundle..."

cd "$WORK_DIR/repo"

if ! tar -czf "../$BUNDLE_NAME" .manifest policies/; then
    log_error "Falha ao compactar bundle"
    exit 1
fi

BUNDLE_SIZE=$(ls -lh "../$BUNDLE_NAME" | awk '{print $5}')
log_success "Bundle compactado: $BUNDLE_SIZE"

log_info "Conteúdo do bundle:"
tar -tzf "../$BUNDLE_NAME"

# ==============================================================================
# PASSO 6: UPLOAD PARA SEAWEEDFS VIA AWS CLI
# ==============================================================================
log_info "Passo 6/6: Enviando bundle para SeaweedFS..."

if ! command -v aws >/dev/null 2>&1; then
    log_error "aws-cli não encontrado."
    log_info "Instale com:"
    echo "   sudo apt install awscli"
    exit 1
fi

export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Criar bucket (idempotente)
log_info "Verificando bucket '${S3_BUCKET}'..."

aws --endpoint-url "${S3_ENDPOINT}" \
    s3 mb "s3://${S3_BUCKET}" >/dev/null 2>&1 || true

if aws --endpoint-url "${S3_ENDPOINT}" \
      s3 ls | awk '{print $3}' | grep -qx "${S3_BUCKET}"; then
    log_success "Bucket '${S3_BUCKET}' disponível."
else
    log_error "Bucket '${S3_BUCKET}' não encontrado."
    exit 1
fi

# Upload
log_info "Enviando ${BUNDLE_NAME}..."

if aws --endpoint-url "${S3_ENDPOINT}" \
        s3 cp "../${BUNDLE_NAME}" \
        "s3://${S3_BUCKET}/${S3_KEY}" >/dev/null; then

    log_success "Upload concluído."

else

    log_error "Falha no upload."
    exit 1

fi

# Verificar no bucket
log_info "Verificando objeto no bucket..."

if aws --endpoint-url "${S3_ENDPOINT}" \
      s3 ls "s3://${S3_BUCKET}/${S3_KEY}" >/dev/null 2>&1; then

    log_success "Objeto encontrado no bucket."

else

    log_error "Objeto não encontrado após upload."
    exit 1

fi

# Verificação via Filer
log_info "Verificando propagação para o Filer..."
sleep 2

VERIFY_STATUS=$(curl -s \
    -o /dev/null \
    -w "%{http_code}" \
    "${FILER_URL}/buckets/${S3_BUCKET}/${S3_KEY}")

if [ "$VERIFY_STATUS" = "200" ]; then

    log_success "Bundle disponível no Filer."

else

    log_warn "Upload realizado, porém o Filer respondeu HTTP ${VERIFY_STATUS}."
    log_warn "Pode haver atraso de sincronização."

fi

# ==============================================================================
# RESUMO FINAL
# ==============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} BUNDLE ATUALIZADO COM SUCESSO!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📦 Bundle:    $BUNDLE_NAME"
echo "🔖 Versão:    $VERSION-$COMMIT_HASH"
echo "📍 S3:        s3://${S3_BUCKET}/${S3_KEY}"
echo "📍 Filer:     ${FILER_URL}/buckets/${S3_BUCKET}/${S3_KEY}"
echo "📏 Tamanho:   $BUNDLE_SIZE"
echo "📄 Rego:      $REGO_COUNT arquivo(s)"
echo ""
echo "📊 Verificar status do OPA:"
echo "   curl -s http://127.0.0.1:8282/v1/status | jq '.result.bundles.trino'"
echo ""
echo "📋 Listar políticas carregadas:"
echo "   curl -s http://127.0.0.1:8282/v1/policies | jq '.result[].id'"
echo ""
echo "🧪 Testar decisão:"
echo "   curl -s -X POST http://127.0.0.1:8282/v1/data/trino/allow \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"input\":{\"context\":{\"identity\":{\"user\":\"admin\"}},\"action\":{\"operation\":\"SelectFromColumns\"}}}' | jq .result"
echo ""