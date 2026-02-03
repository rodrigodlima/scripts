#!/bin/bash

# Script para remover todos os buckets S3 da AWS
# ATENÇÃO: Este script é DESTRUTIVO e irá remover TODOS os buckets e seus conteúdos
# Use com EXTREMO CUIDADO!

set -e  # Para execução em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para log
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verifica se AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI não está instalado. Instale com: pip install awscli"
    exit 1
fi

# Verifica se as credenciais AWS estão configuradas
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "Credenciais AWS não configuradas ou inválidas"
    exit 1
fi

# Mostra informações da conta
log_info "Conta AWS atual:"
aws sts get-caller-identity

echo ""
log_warning "════════════════════════════════════════════════════════════"
log_warning "ATENÇÃO: Este script irá DELETAR TODOS os buckets S3!"
log_warning "Todos os arquivos e versões serão PERMANENTEMENTE removidos!"
log_warning "════════════════════════════════════════════════════════════"
echo ""

# Lista todos os buckets
log_info "Listando todos os buckets S3..."
buckets=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

if [ -z "$buckets" ]; then
    log_info "Nenhum bucket encontrado na conta."
    exit 0
fi

echo ""
log_info "Buckets encontrados:"
echo "$buckets" | tr '\t' '\n' | nl
echo ""

# Confirmação do usuário
read -p "Tem certeza que deseja deletar TODOS esses buckets? Digite 'DELETE-ALL' para confirmar: " confirmation

if [ "$confirmation" != "DELETE-ALL" ]; then
    log_info "Operação cancelada pelo usuário."
    exit 0
fi

echo ""
log_warning "Iniciando processo de deleção..."
echo ""

# Contador
total_buckets=0
deleted_buckets=0
failed_buckets=0

# Processa cada bucket
for bucket in $buckets; do
    total_buckets=$((total_buckets + 1))
    log_info "Processando bucket: $bucket"
    
    # Verifica a região do bucket
    region=$(aws s3api get-bucket-location --bucket "$bucket" --query "LocationConstraint" --output text 2>/dev/null || echo "us-east-1")
    if [ "$region" == "None" ] || [ -z "$region" ]; then
        region="us-east-1"
    fi
    
    log_info "  Região: $region"
    
    # Remove versionamento se habilitado
    log_info "  Verificando versionamento..."
    versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --region "$region" --query "Status" --output text 2>/dev/null || echo "")
    
    if [ "$versioning" == "Enabled" ]; then
        log_warning "  Versionamento habilitado. Removendo todas as versões..."
        
        # Remove todas as versões de objetos
        aws s3api list-object-versions --bucket "$bucket" --region "$region" --output json | \
        jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key versionId; do
            if [ -n "$key" ] && [ -n "$versionId" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$versionId" --region "$region" &>/dev/null
            fi
        done
    fi
    
    # Remove todos os objetos normais
    log_info "  Removendo objetos..."
    object_count=$(aws s3 ls "s3://$bucket" --recursive --region "$region" 2>/dev/null | wc -l || echo "0")
    
    if [ "$object_count" -gt 0 ]; then
        log_info "  Encontrados $object_count objetos"
        aws s3 rm "s3://$bucket" --recursive --region "$region" &>/dev/null || {
            log_error "  Falha ao remover objetos do bucket $bucket"
        }
    fi
    
    # Remove o bucket
    log_info "  Removendo bucket..."
    if aws s3api delete-bucket --bucket "$bucket" --region "$region" 2>/dev/null; then
        log_info "  ✓ Bucket $bucket deletado com sucesso!"
        deleted_buckets=$((deleted_buckets + 1))
    else
        log_error "  ✗ Falha ao deletar bucket $bucket"
        failed_buckets=$((failed_buckets + 1))
    fi
    
    echo ""
done

# Resumo final
echo ""
log_info "════════════════════════════════════════════════════════════"
log_info "Resumo da Operação:"
log_info "  Total de buckets processados: $total_buckets"
log_info "  Buckets deletados com sucesso: $deleted_buckets"
if [ $failed_buckets -gt 0 ]; then
    log_error "  Buckets com falha: $failed_buckets"
fi
log_info "════════════════════════════════════════════════════════════"
