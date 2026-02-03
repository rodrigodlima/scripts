#!/bin/bash

# Versão SIMPLES - Remove todos os buckets S3
# ATENÇÃO: SCRIPT DESTRUTIVO!

# Cores
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}ATENÇÃO: Este script irá deletar TODOS os buckets S3!${NC}"
read -p "Digite 'SIM' para confirmar: " confirm

if [ "$confirm" != "SIM" ]; then
    echo "Cancelado."
    exit 0
fi

# Lista e remove cada bucket
for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
    echo -e "${YELLOW}Processando: $bucket${NC}"
    
    # Remove objetos (incluindo versionados)
    aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
    
    # Remove versões antigas se houver
    aws s3api delete-objects --bucket "$bucket" \
        --delete "$(aws s3api list-object-versions --bucket "$bucket" \
        --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null)" \
        2>/dev/null || true
    
    # Remove delete markers
    aws s3api delete-objects --bucket "$bucket" \
        --delete "$(aws s3api list-object-versions --bucket "$bucket" \
        --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null)" \
        2>/dev/null || true
    
    # Remove o bucket
    aws s3api delete-bucket --bucket "$bucket" 2>/dev/null && \
        echo "✓ Deletado: $bucket" || \
        echo "✗ Erro ao deletar: $bucket"
done

echo "Processo finalizado!"
