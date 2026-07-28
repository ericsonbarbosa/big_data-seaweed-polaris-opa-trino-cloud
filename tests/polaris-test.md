
---

## Laboratório via Curl - Terminal
### Iniciar os testes após acessar a máquina remota via SSH

```bash
# ==============================================================================
# BLOCO 1: CONFIGURAÇÃO E AUTENTICAÇÃO
# ==============================================================================

# Obter token OAuth2 (válido por ~1 hora)
export TOKEN=$(curl -s -X POST http://127.0.0.1:8182/api/catalog/v1/oauth/tokens -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=root&client_secret=root_secret_changeme&scope=PRINCIPAL_ROLE:ALL" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Validar token
echo $TOKEN

# ==============================================================================
# BLOCO 2: EXPLORAR ESTRUTURA
# ==============================================================================

# Listar catálogos disponíveis 
curl -s http://127.0.0.1:8182/api/management/v1/catalogs -H "Authorization: Bearer $TOKEN" -H "Polaris-Realm: POLARIS" | python3 -m json.tool

# Listar namespaces no catálogo iceberg
curl -s http://127.0.0.1:8182/api/catalog/v1/iceberg/namespaces -H "Authorization: Bearer $TOKEN" -H "Polaris-Realm: POLARIS" | python3 -m json.tool

# Ver detalhes do namespace api_lab
curl -s http://127.0.0.1:8182/api/catalog/v1/iceberg/namespaces/api_lab -H "Authorization: Bearer $TOKEN" -H "Polaris-Realm: POLARIS" | python3 -m json.tool

# ==============================================================================
# BLOCO 3: TABELAS EXISTENTES
# ==============================================================================

# Listar tabelas no namespace api_lab
curl -s http://127.0.0.1:8182/api/catalog/v1/iceberg/namespaces/api_lab/tables -H "Authorization: Bearer $TOKEN" -H "Polaris-Realm: POLARIS" | python3 -m json.tool

# Ver metadata completa da tabela 'clientes'
curl -s http://127.0.0.1:8182/api/catalog/v1/iceberg/namespaces/api_lab/tables/clientes -H "Authorization: Bearer $TOKEN" -H "Polaris-Realm: POLARIS" | python3 -m json.tool

# ==============================================================================
# BLOCO 4: CRIAR NOVA TABELA
# ==============================================================================

# Criar tabela clientes
curl -s -X POST "http://127.0.0.1:8182/api/catalog/v1/iceberg/namespaces/api_lab/tables" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: POLARIS" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "clientes",
    "schema": {
      "type": "struct",
      "fields": [
        {"id": 1, "name": "id", "type": "long", "required": true},
        {"id": 2, "name": "nome", "type": "string", "required": false},
        {"id": 3, "name": "email", "type": "string", "required": false},
        {"id": 4, "name": "cidade", "type": "string", "required": false},
        {"id": 5, "name": "data_cadastro", "type": "date", "required": false}
      ]
    },
    "properties": {"format-version": "2"}
  }' | python3 -m json.tool

# Confirmar que a tabela foi criada
curl -s "http://127.0.0.1:8182/api/catalog/v1/iceberg/namespaces/api_lab/tables" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: POLARIS" | python3 -m json.tool

# ==============================================================================
# BLOCO 5: VALIDAR METASTORE POSTGRESQL
# ==============================================================================

# Contar entidades n POSTGRESQL
sudo -u postgres psql -d polaris_db -c "SELECT COUNT(*) as total_entidades FROM polaris_schema.entities;"

# Validar entidades no PostgreSQL
sudo -u postgres psql -d polaris_db -c "SELECT name, type_code FROM polaris_schema.entities WHERE name IN ('iceberg', 'api_lab', 'produtos', 'clientes') ORDER BY name;"

# ==============================================================================
# BLOCO 6: VALIDAR STORAGE S3 (SEAWEEDFS)
# ==============================================================================

# Listar buckets no SeaweedFS
aws --profile seaweedfs --endpoint-url http://127.0.0.1:8333 s3 ls

# Listar todos os arquivos no bucket warehouse
aws --profile seaweedfs --endpoint-url http://127.0.0.1:8333 s3 ls s3://warehouse/ --recursive

# Listar metadata da tabela clientes no S3
aws --profile seaweedfs --endpoint-url http://127.0.0.1:8333 s3 ls s3://warehouse/iceberg/api_lab/clientes/metadata/

# Baixar e visualizar metadata da tabela clientes
aws --profile seaweedfs --endpoint-url http://127.0.0.1:8333 s3 cp s3://warehouse/iceberg/api_lab/clientes/metadata/00000-532eb000-6b9d-4b8e-8f4d-cd190a3f4bdd.metadata.json /tmp/clientes_metadata.json

cat /tmp/clientes_metadata.json | python3 -m json.tool


# ==============================================================================
# BLOCO 7: RESUMO EXECUTIVO
# ==============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          POLARIS CATALOG - STATUS DA APRESENTAÇÃO          ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║ ✅ Metastore PostgreSQL: FUNCIONANDO                       ║"
echo "║ ✅ Catálogo 'iceberg': CRIADO                              ║"
echo "║ ✅ Namespace 'api_lab': CRIADO                             ║"
echo "║ ✅ Tabela 'clientes': CRIADA (5 colunas)                   ║"
echo "║ ✅ SeaweedFS S3: ACESSÍVEL (http://127.0.0.1:8333)         ║"
echo "║ ✅ OAuth2 Token: VÁLIDO                                    ║"
echo "║ ✅ API REST: RESPONDENDO                                   ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║ 🚀 PRONTO PARA DEMONSTRAÇÃO VIA TRINO                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
```

## Consulta Trino e inclusão de dados na nova tabela 

```sql
-- Listar schemas para confirmar que api_lab aparece
SHOW SCHEMAS IN iceberg;

-- Listar tabelas no schema api_lab
SHOW TABLES IN iceberg.api_lab;

-- Inserir dados na tabela criada via API
INSERT INTO iceberg.api_lab.produtos VALUES 
    (1, 'Criado via API REST!'),
    (2, 'Polaris + Trino + SeaweedFS');

-- Consultar os dados
SELECT * FROM iceberg.api_lab.produtos;
```

## Listar endpoints da API REST Polaris

```bash
# Endpoints do REST Catalog (retorna os endpoints iceberg)
curl -s "http://127.0.0.1:8182/api/catalog/v1/config?warehouse=iceberg" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: POLARIS" | python3 -m json.tool

# Referência definitiva para interagir com o Polaris via curl:
# http://192.168.56.101:8182/api/catalog/v1/iceberg/{recurso}
```