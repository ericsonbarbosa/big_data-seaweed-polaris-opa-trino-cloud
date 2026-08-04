#!/bin/bash
# ==============================================================================
# Testes da policy portal.rego via curl
# Uso: ./test-portal-opa.sh [OPA_HOST]
# Exemplo: ./test-portal-opa.sh http://SEU_IP:8282
# ==============================================================================

OPA_HOST="${1:-http://localhost:8282}"
BASE_URL="$OPA_HOST/v1/data/portal/authz"

# Tokens do data.json
TOKEN1="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjb2xlY2FvIjoiNjg0NzQzOWE5ODU5YjIxMjU2OTZkYmNjIiwiaWF0IjoxNzQ5NTAwODI2fQ.icfp7TTqYpQdGdDs3-zVc_rNxbgxmNXAQ3jRxeNBV6M"
TOKEN2="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjb2xlY2FvIjoiNjg0NzM1ZTcxYjZiODQ3YWU3OTQ0YWEzIiwidXN1YXJpbyI6IjY0OWIzOTZkZTk3ZjhiNTI2YzQ1ZDE1NCIsImlhdCI6MTc0OTUwMTM4MX0.XsliM8_VQ7hBjf7TnQJ_7L_fKMhJ8iGs7srdwc6tiY4"
TOKEN_INVALIDO="token.invalido.qualquer"

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

secao() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}══════════════════════════════════════${NC}"; }
ok()     { echo -e "${GREEN}[ESPERADO: true ]${NC} $1"; }
nok()    { echo -e "${RED}[ESPERADO: false]${NC} $1"; }
info()   { echo -e "${YELLOW}[INFO]${NC} $1"; }

query() {
    local endpoint="$1"
    local payload="$2"
    curl -s -X POST "$BASE_URL/$endpoint" \
        -H "Content-Type: application/json" \
        -d "$payload" | python3 -m json.tool 2>/dev/null || echo "(sem resposta)"
}

# ==============================================================================
# TOKEN 1 — teste_poseidon2 (tipo_campos: Completo, sem anonimização)
# ==============================================================================
secao "TOKEN 1 — teste_poseidon2 (Completo)"

ok "Acesso à coleção correta"
query "allow" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_poseidon2\",\"campo\":\"emp_no\"}}"

ok "Campo emp_no permitido"
query "allow" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_poseidon2\",\"campo\":\"emp_no\"}}"

ok "Campo hire_date permitido"
query "allow" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_poseidon2\",\"campo\":\"hire_date\"}}"

nok "Campo NÃO existente na lista"
query "allow" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_poseidon2\",\"campo\":\"salary\"}}"

nok "Coleção errada com token correto"
query "allow" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_cpf\"}}"

info "collection_info do TOKEN1"
query "collection_info" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_poseidon2\"}}"

info "required_filters do TOKEN1"
query "required_filters" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_poseidon2\"}}"

info "has_anonymization em emp_no (esperado: false/undefined)"
query "has_anonymization" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_poseidon2\",\"campo\":\"emp_no\"}}"

# ==============================================================================
# TOKEN 2 — teste_entidades (tipo_campos: Selecionados, com anonimização CPF)
# ==============================================================================
secao "TOKEN 2 — teste_entidades (Selecionados + Anonimização)"

ok "Campo candidato_nome permitido"
query "allow" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_nome\"}}"

ok "Campo candidato_cpf permitido (mas será anonimizado)"
query "allow" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_cpf\"}}"

nok "Campo NÃO permitido (fora da lista selecionada)"
query "allow" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_rg\"}}"

nok "Coleção errada com token correto"
query "allow" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_poseidon2\",\"campo\":\"emp_no\"}}"

ok "tipo_query=api compatível com perm.tipo_query"
query "allow" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_cpf\",\"tipo_query\":\"api\"}}"

nok "tipo_query=sql incompatível"
query "allow" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_cpf\",\"tipo_query\":\"sql\"}}"

info "has_anonymization em candidato_cpf (esperado: true)"
query "has_anonymization" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_cpf\"}}"

info "has_anonymization em candidato_nome (esperado: false/undefined)"
query "has_anonymization" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_nome\"}}"

info "anonymize_rule para candidato_cpf"
query "anonymize_rule" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_cpf\"}}"

info "columnMask para candidato_cpf (esperado: token-sha256 → '***')"
query "columnMask" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_cpf\"}}"

info "collection_info do TOKEN2"
query "collection_info" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\"}}"

info "required_filters do TOKEN2"
query "required_filters" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\"}}"

# ==============================================================================
# TOKEN INVÁLIDO — deve negar tudo
# ==============================================================================
secao "TOKEN INVÁLIDO — deve negar tudo"

nok "Token inválido com coleção válida"
query "allow" "{\"input\":{\"token\":\"$TOKEN_INVALIDO\",\"colecao\":\"teste_poseidon2\",\"campo\":\"emp_no\"}}"

info "Mensagem de deny para token inválido"
query "deny" "{\"input\":{\"token\":\"$TOKEN_INVALIDO\",\"colecao\":\"teste_poseidon2\",\"campo\":\"emp_no\"}}"

# ==============================================================================
# AUDITORIA — mensagens de deny
# ==============================================================================
secao "AUDITORIA — mensagens de deny"

info "Deny com campo não permitido (TOKEN2 + campo inválido)"
query "deny" "{\"input\":{\"token\":\"$TOKEN2\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_rg\"}}"

info "Deny com coleção errada (TOKEN1 + coleção do TOKEN2)"
query "deny" "{\"input\":{\"token\":\"$TOKEN1\",\"colecao\":\"teste_entidades\",\"campo\":\"candidato_cpf\"}}"

echo -e "\n${GREEN}Testes concluídos.${NC}"
echo -e "OPA testado em: $BASE_URL"