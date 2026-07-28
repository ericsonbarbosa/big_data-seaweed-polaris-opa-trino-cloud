# Testes de sitema as portas SeaweedFS

## Teste 1 - Verificação dos serviços SeaweedFS

| Serviço               | URL                               | Descrição                                                                 |
|-----------------------|-----------------------------------|---------------------------------------------------------------------------|
| SeaweedFS Master      | http://192.168.56.101:9333        | Painel de status do cluster (volumes ativos, health checks)               |
| SeaweedFS Filer       | http://192.168.56.101:8888        | Interface web tipo "Google Drive" para navegar pelos arquivos do data lake |
| SeaweedFS S3 Gateway  | http://192.168.56.101:8333        | Endpoint compatível com S3 (retorna XML com informações do bucket) 

## Extra: Validação no seaweedfs-node dos volumes via shell:
```bash
# SeaweedFS retorno dos volumes 
echo "ls /" | weed shell -master=localhost:9333
```
Retorno esperado:  
***buckets***  
***topics***

```bash
# Listar os namespaces dentro do buckets com "ls"
aws --profile seaweedfs --endpoint-url http://127.0.0.1:8333 s3 ls

# Listar todos os arquivos no bucket warehouse
aws --profile seaweedfs --endpoint-url http://127.0.0.1:8333 s3 ls s3://warehouse/ --recursive
```
