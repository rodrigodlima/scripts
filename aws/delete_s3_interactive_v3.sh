#!/bin/bash

# Script para deletar buckets S3 com seleção interativa
# Versão OTIMIZADA com feedback em tempo real

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_progress() { echo -e "${CYAN}[PROGRESS]${NC} $1"; }

# Verifica AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI não instalado"
    exit 1
fi

# Verifica credenciais
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "Credenciais AWS inválidas"
    exit 1
fi

log_info "Conta AWS:"
aws sts get-caller-identity

echo ""
log_info "Listando buckets S3..."

# Cria arquivo temporário com a lista de buckets
TEMP_FILE=$(mktemp)
aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' > "$TEMP_FILE"

# Verifica se há buckets
if [ ! -s "$TEMP_FILE" ]; then
    log_info "Nenhum bucket encontrado."
    rm -f "$TEMP_FILE"
    exit 0
fi

# Mostra buckets com índices
echo ""
log_info "Buckets disponíveis:"
line_num=1
while IFS= read -r bucket; do
    echo -e "  ${BLUE}[$line_num]${NC} $bucket"
    line_num=$((line_num + 1))
done < "$TEMP_FILE"

total_buckets=$((line_num - 1))

echo ""
log_warning "Selecione os buckets para deletar:"
echo "  • Digite os números separados por espaço (ex: 1 3 5)"
echo "  • Digite 'all' para selecionar todos"
echo "  • Digite 'q' para cancelar"
echo ""

read -p "Seleção: " selection

# Processa seleção
if [ "$selection" == "q" ]; then
    log_info "Operação cancelada."
    rm -f "$TEMP_FILE"
    exit 0
fi

# Cria arquivo temporário para buckets selecionados
SELECTED_FILE=$(mktemp)

if [ "$selection" == "all" ]; then
    cp "$TEMP_FILE" "$SELECTED_FILE"
else
    for num in $selection; do
        if ! [[ "$num" =~ ^[0-9]+$ ]]; then
            log_warning "Entrada inválida ignorada: $num"
            continue
        fi
        
        if [ "$num" -ge 1 ] && [ "$num" -le "$total_buckets" ]; then
            sed -n "${num}p" "$TEMP_FILE" >> "$SELECTED_FILE"
        else
            log_warning "Índice fora do intervalo ignorado: $num"
        fi
    done
fi

# Verifica se há buckets selecionados
if [ ! -s "$SELECTED_FILE" ]; then
    log_error "Nenhum bucket válido selecionado."
    rm -f "$TEMP_FILE" "$SELECTED_FILE"
    exit 1
fi

# Mostra seleção
echo ""
log_warning "Buckets selecionados para DELEÇÃO:"
while IFS= read -r bucket; do
    echo -e "  ${RED}✗${NC} $bucket"
done < "$SELECTED_FILE"

echo ""
read -p "Confirmar deleção? Digite 'DELETE' para confirmar: " confirm

if [ "$confirm" != "DELETE" ]; then
    log_info "Operação cancelada."
    rm -f "$TEMP_FILE" "$SELECTED_FILE"
    exit 0
fi

# Deleta buckets selecionados
echo ""
deleted=0
failed=0

while IFS= read -r bucket; do
    log_info "════════════════════════════════════════════════"
    log_info "Processando: $bucket"
    
    # Obtém região
    log_progress "Detectando região..."
    region=$(aws s3api get-bucket-location --bucket "$bucket" --query "LocationConstraint" --output text 2>/dev/null || echo "us-east-1")
    if [ "$region" == "None" ] || [ -z "$region" ]; then
        region="us-east-1"
    fi
    log_info "  Região: $region"
    
    # Verifica versionamento
    log_progress "Verificando versionamento..."
    versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --region "$region" --query "Status" --output text 2>/dev/null || echo "Disabled")
    log_info "  Versionamento: $versioning"
    
    # Conta objetos primeiro
    log_progress "Contando objetos e versões..."
    
    if [ "$versioning" == "Enabled" ]; then
        # Conta versões
        version_count=$(aws s3api list-object-versions --bucket "$bucket" --region "$region" --output json 2>/dev/null | \
            jq -r '[.Versions[]?, .DeleteMarkers[]?] | length' 2>/dev/null || echo "0")
        
        log_info "  Total de versões encontradas: $version_count"
        
        if [ "$version_count" -gt 0 ]; then
            log_warning "  Removendo $version_count versões (pode demorar)..."
            
            # Usa batch delete em vez de um por um
            versions_json=$(mktemp)
            
            # Pega todas as versões e delete markers
            aws s3api list-object-versions --bucket "$bucket" --region "$region" --output json 2>/dev/null | \
                jq -r '.Versions[]?, .DeleteMarkers[]? | {Key: .Key, VersionId: .VersionId}' 2>/dev/null > "$versions_json"
            
            # Conta linhas processadas para mostrar progresso
            total_lines=$(wc -l < "$versions_json")
            processed=0
            batch_size=0
            batch_json="[]"
            
            while IFS= read -r line; do
                # Adiciona ao batch
                batch_json=$(echo "$batch_json" | jq --argjson obj "$line" '. += [$obj]' 2>/dev/null)
                batch_size=$((batch_size + 1))
                processed=$((processed + 1))
                
                # Processa em lotes de 1000 ou no final
                if [ "$batch_size" -eq 1000 ] || [ "$processed" -eq "$total_lines" ]; then
                    if [ "$batch_size" -gt 0 ]; then
                        log_progress "  Deletando lote ($(($processed - $batch_size + 1))-$processed de $total_lines)..."
                        
                        # Deleta o batch
                        echo "{\"Objects\": $batch_json, \"Quiet\": true}" | \
                            aws s3api delete-objects --bucket "$bucket" --region "$region" --delete file:///dev/stdin &>/dev/null || true
                        
                        # Reset batch
                        batch_json="[]"
                        batch_size=0
                    fi
                fi
            done < "$versions_json"
            
            rm -f "$versions_json"
            log_info "  ${GREEN}✓${NC} Versões removidas"
        fi
    else
        # Bucket sem versionamento - conta objetos normais
        object_count=$(aws s3 ls "s3://$bucket" --recursive --region "$region" 2>/dev/null | wc -l || echo "0")
        log_info "  Objetos encontrados: $object_count"
        
        if [ "$object_count" -gt 0 ]; then
            log_progress "  Removendo $object_count objetos..."
            aws s3 rm "s3://$bucket" --recursive --region "$region" --only-show-errors 2>&1 | \
                grep -v "^$" | head -20 || true
            log_info "  ${GREEN}✓${NC} Objetos removidos"
        fi
    fi
    
    # Remove bucket
    log_progress "Removendo bucket vazio..."
    if aws s3api delete-bucket --bucket "$bucket" --region "$region" 2>/dev/null; then
        log_info "${GREEN}✓✓✓ Bucket $bucket deletado com sucesso!${NC}"
        deleted=$((deleted + 1))
    else
        log_error "${RED}✗✗✗ Falha ao deletar bucket $bucket${NC}"
        log_error "Possíveis causas: bucket não vazio, políticas de retenção, ou permissões"
        failed=$((failed + 1))
    fi
    echo ""
done < "$SELECTED_FILE"

# Limpa arquivos temporários
rm -f "$TEMP_FILE" "$SELECTED_FILE"

# Resumo
echo ""
log_info "════════════════════════════════════════════════"
log_info "RESUMO FINAL:"
log_info "  ${GREEN}Deletados com sucesso: $deleted${NC}"
[ $failed -gt 0 ] && log_error "  ${RED}Falhas: $failed${NC}"
log_info "════════════════════════════════════════════════"
