# Testes de Sistema Postgres
## Teste 1 - Listar todas as tabelas do Metastore (incluindo as de sistema)

```bash
# Listar schemas disponíveis
sudo -u postgres psql -d polaris_db -c "\dn"

# Listar todas as entidades (catálogos, namespaces, tabelas, principals)
sudo -u postgres psql -d polaris_db -c "SELECT id, name, type_code, parent_id FROM polaris_schema.entities ORDER BY type_code, name;"

# Ver apenas catálogos (type_code = 4)
sudo -u postgres psql -d polaris_db -c "SELECT id, name FROM polaris_schema.entities WHERE type_code = 4;"

# Ver apenas namespaces (type_code = 6)
sudo -u postgres psql -d polaris_db -c "SELECT id, name, parent_id FROM polaris_schema.entities WHERE type_code = 6;"

# Ver apenas tabelas Iceberg (type_code = 7)
sudo -u postgres psql -d polaris_db -c "SELECT id, name, parent_id, location_without_scheme FROM polaris_schema.entities WHERE type_code = 7;"



```

Você verá algo como:

```text
            List of relations
 Schema |       Name        | Type  | Owner 
--------+-------------------+-------+-------
 public | AUX_TABLE         | table | hive
 public | BUCKETING_COLS    | table | hive
 public | CDS               | table | hive
 public | COLUMNS_V2        | table | hive
 public | COMPACTION_QUEUE  | table | hive
 public | COMPLETED_TXN_COMPONENTS | table | hive
 public | DATABASE_PARAMS   | table | hive
 public | DBS               | table | hive
 public | DB_PRIVS          | table | hive
 public | DELEGATION_TOKENS | table | hive
```

## Teste 2 - Consultar a versão do Metastore

```bash
sudo -u postgres psql -d polaris_db -c "SELECT * FROM \"VERSION\";"
```

Saída típica:

```text
 VER_ID | SCHEMA_VERSION | VERSION_COMMENT 
--------+----------------+-----------------
      1 | 3.1.0          | Hive release version 3.1.0
```