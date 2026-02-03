#!/bin/bash

# Script DRY-RUN - Mostra o que SERIA deletado sem deletar de fato
# Útil para testar antes de executar a deleção real

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         DRY-RUN - Análise de Buckets S3               ║${NC}"
echo -e "${CYAN}║    (Nenhuma ação destrutiva será executada)            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verifica AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${YELLOW}AWS CLI não instalado${NC}"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Conta AWS:"
aws sts get-caller-identity
echo ""

echo -e "${GREEN}[INFO]${NC} Analisando buckets S3..."
echo ""

# Estatísticas
total_buckets=0
total_objects=0
total_size_bytes=0
declare -A bucket_stats

# Processa cada bucket
for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
    total_buckets=$((total_buckets + 1))
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Bucket:${NC} $bucket"
    
    # Região
    region=$(aws s3api get-bucket-location --bucket "$bucket" --query "LocationConstraint" --output text 2>/dev/null || echo "us-east-1")
    [ "$region" == "None" ] && region="us-east-1"
    echo -e "  ${GREEN}Região:${NC} $region"
    
    # Versionamento
    versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --region "$region" --query "Status" --output text 2>/dev/null || echo "Disabled")
    echo -e "  ${GREEN}Versionamento:${NC} $versioning"
    
    # Conta objetos e tamanho
    echo -n "  ${GREEN}Analisando objetos...${NC} "
    object_info=$(aws s3 ls "s3://$bucket" --recursive --summarize --region "$region" 2>/dev/null | tail -n 2)
    
    object_count=$(echo "$object_info" | grep "Total Objects:" | awk '{print $3}' || echo "0")
    size=$(echo "$object_info" | grep "Total Size:" | awk '{print $3}' || echo "0")
    
    if [ -z "$object_count" ]; then object_count=0; fi
    if [ -z "$size" ]; then size=0; fi
    
    echo "OK"
    echo -e "  ${GREEN}Objetos:${NC} $object_count"
    echo -e "  ${GREEN}Tamanho:${NC} $(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "${size} bytes")"
    
    # Versões (se versionamento habilitado)
    if [ "$versioning" == "Enabled" ]; then
        version_count=$(aws s3api list-object-versions --bucket "$bucket" --region "$region" --query 'length(Versions)' 2>/dev/null || echo "0")
        marker_count=$(aws s3api list-object-versions --bucket "$bucket" --region "$region" --query 'length(DeleteMarkers)' 2>/dev/null || echo "0")
        echo -e "  ${YELLOW}Versões de objetos:${NC} $version_count"
        echo -e "  ${YELLOW}Delete markers:${NC} $marker_count"
    fi
    
    # Tags
    tags=$(aws s3api get-bucket-tagging --bucket "$bucket" --region "$region" 2>/dev/null | jq -r '.TagSet[]? | "\(.Key)=\(.Value)"' 2>/dev/null)
    if [ -n "$tags" ]; then
        echo -e "  ${GREEN}Tags:${NC}"
        echo "$tags" | while read tag; do
            echo "    - $tag"
        done
    fi
    
    # Acumula estatísticas
    total_objects=$((total_objects + object_count))
    total_size_bytes=$((total_size_bytes + size))
    
    echo ""
done

# Resumo final
echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  RESUMO DA ANÁLISE                     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Total de Buckets:${NC} $total_buckets"
echo -e "${GREEN}Total de Objetos:${NC} $total_objects"
echo -e "${GREEN}Tamanho Total:${NC} $(numfmt --to=iec-i --suffix=B $total_size_bytes 2>/dev/null || echo "${total_size_bytes} bytes")"
echo ""

# Estimativa de tempo
echo -e "${YELLOW}Estimativas:${NC}"
echo -e "  - Tempo estimado de deleção: ~$((total_buckets * 30)) segundos"
echo -e "  - Operações de API necessárias: ~$((total_objects + total_buckets))"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Análise concluída!${NC}"
echo ""
echo -e "${YELLOW}Para deletar estes buckets, execute:${NC}"
echo "  ./delete_all_s3_buckets.sh    (completo)"
echo "  ./delete_s3_simple.sh         (rápido)"
echo "  ./delete_s3_interactive.sh    (seletivo)"
