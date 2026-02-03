#!/bin/bash

# Script para fazer BACKUP dos buckets S3 antes de deletar
# Cria cópias locais de todos os buckets

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Diretório de backup
BACKUP_DIR="./s3-backup-$(date +%Y%m%d-%H%M%S)"
METADATA_FILE="$BACKUP_DIR/metadata.json"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Backup de Buckets S3 antes de Deletar        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verifica AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI não instalado"
    exit 1
fi

# Verifica jq
if ! command -v jq &> /dev/null; then
    log_warning "jq não instalado. Metadados em JSON podem não funcionar corretamente."
fi

# Mostra conta
log_info "Conta AWS:"
aws sts get-caller-identity
echo ""

# Cria diretório de backup
mkdir -p "$BACKUP_DIR"
log_info "Diretório de backup: $BACKUP_DIR"
echo ""

# Lista buckets
buckets=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

if [ -z "$buckets" ]; then
    log_info "Nenhum bucket encontrado."
    exit 0
fi

log_info "Buckets encontrados:"
echo "$buckets" | tr '\t' '\n' | nl
echo ""

# Confirmação
read -p "Deseja fazer backup de todos esses buckets? (s/N): " confirm
if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
    log_info "Operação cancelada."
    exit 0
fi

# Inicializa metadata
echo "{" > "$METADATA_FILE"
echo "  \"backup_date\": \"$(date -Iseconds)\"," >> "$METADATA_FILE"
echo "  \"account\": $(aws sts get-caller-identity | jq -c .)," >> "$METADATA_FILE"
echo "  \"buckets\": [" >> "$METADATA_FILE"

first_bucket=true
successful_backups=0
failed_backups=0

# Backup de cada bucket
for bucket in $buckets; do
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Fazendo backup de: $bucket"
    
    bucket_dir="$BACKUP_DIR/$bucket"
    mkdir -p "$bucket_dir"
    
    # Região
    region=$(aws s3api get-bucket-location --bucket "$bucket" --query "LocationConstraint" --output text 2>/dev/null || echo "us-east-1")
    [ "$region" == "None" ] && region="us-east-1"
    log_info "  Região: $region"
    
    # Metadados do bucket
    log_info "  Salvando metadados..."
    
    # Versionamento
    versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --region "$region" 2>/dev/null || echo '{"Status":"Disabled"}')
    echo "$versioning" > "$bucket_dir/versioning.json"
    
    # Tags
    tags=$(aws s3api get-bucket-tagging --bucket "$bucket" --region "$region" 2>/dev/null || echo '{"TagSet":[]}')
    echo "$tags" > "$bucket_dir/tags.json"
    
    # Políticas
    policy=$(aws s3api get-bucket-policy --bucket "$bucket" --region "$region" 2>/dev/null || echo '{}')
    echo "$policy" > "$bucket_dir/policy.json"
    
    # ACL
    acl=$(aws s3api get-bucket-acl --bucket "$bucket" --region "$region" 2>/dev/null || echo '{}')
    echo "$acl" > "$bucket_dir/acl.json"
    
    # Lifecycle
    lifecycle=$(aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" --region "$region" 2>/dev/null || echo '{}')
    echo "$lifecycle" > "$bucket_dir/lifecycle.json"
    
    # CORS
    cors=$(aws s3api get-bucket-cors --bucket "$bucket" --region "$region" 2>/dev/null || echo '{}')
    echo "$cors" > "$bucket_dir/cors.json"
    
    # Download dos objetos
    log_info "  Baixando objetos..."
    object_count=$(aws s3 ls "s3://$bucket" --recursive --region "$region" 2>/dev/null | wc -l || echo "0")
    
    if [ "$object_count" -gt 0 ]; then
        log_info "  Encontrados $object_count objetos"
        
        if aws s3 sync "s3://$bucket" "$bucket_dir/objects" --region "$region" 2>&1 | tee "$bucket_dir/sync.log"; then
            log_info "  ${GREEN}✓${NC} Backup concluído com sucesso!"
            successful_backups=$((successful_backups + 1))
            backup_status="success"
        else
            log_error "  ${RED}✗${NC} Erro no backup"
            failed_backups=$((failed_backups + 1))
            backup_status="failed"
        fi
    else
        log_info "  Bucket vazio"
        backup_status="empty"
        successful_backups=$((successful_backups + 1))
    fi
    
    # Adiciona ao metadata
    if [ "$first_bucket" = false ]; then
        echo "," >> "$METADATA_FILE"
    fi
    first_bucket=false
    
    cat >> "$METADATA_FILE" <<EOF
    {
      "name": "$bucket",
      "region": "$region",
      "object_count": $object_count,
      "backup_status": "$backup_status",
      "backup_path": "$bucket_dir"
    }
EOF
    
    echo ""
done

# Finaliza metadata
echo "" >> "$METADATA_FILE"
echo "  ]" >> "$METADATA_FILE"
echo "}" >> "$METADATA_FILE"

# Resumo
log_info "════════════════════════════════════════════════════════"
log_info "Resumo do Backup:"
log_info "  Total de buckets: $(echo "$buckets" | wc -w)"
log_info "  Backups bem-sucedidos: $successful_backups"
if [ $failed_backups -gt 0 ]; then
    log_error "  Backups com falha: $failed_backups"
fi
log_info "  Diretório de backup: $BACKUP_DIR"
log_info "════════════════════════════════════════════════════════"
echo ""

# Cria script de restore
log_info "Criando script de restore..."
cat > "$BACKUP_DIR/restore.sh" <<'EOF'
#!/bin/bash
# Script de RESTORE dos buckets

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Script de Restore de Buckets S3${NC}"
echo ""

read -p "Tem certeza que deseja restaurar os buckets? (s/N): " confirm
if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
    echo "Cancelado."
    exit 0
fi

for bucket_dir in */; do
    bucket="${bucket_dir%/}"
    
    if [ "$bucket" == "*" ]; then
        continue
    fi
    
    echo -e "${GREEN}Restaurando: $bucket${NC}"
    
    # Cria bucket
    region=$(cat "$bucket_dir/versioning.json" | jq -r '.Status' 2>/dev/null || echo "us-east-1")
    aws s3 mb "s3://$bucket" --region "$region" 2>/dev/null || echo "  Bucket já existe"
    
    # Restaura objetos
    if [ -d "$bucket_dir/objects" ]; then
        aws s3 sync "$bucket_dir/objects" "s3://$bucket" --region "$region"
    fi
    
    # Restaura configurações
    [ -f "$bucket_dir/tags.json" ] && aws s3api put-bucket-tagging --bucket "$bucket" --tagging "file://$bucket_dir/tags.json" 2>/dev/null
    [ -f "$bucket_dir/policy.json" ] && aws s3api put-bucket-policy --bucket "$bucket" --policy "file://$bucket_dir/policy.json" 2>/dev/null
    [ -f "$bucket_dir/cors.json" ] && aws s3api put-bucket-cors --bucket "$bucket" --cors-configuration "file://$bucket_dir/cors.json" 2>/dev/null
    
    echo ""
done

echo -e "${GREEN}Restore concluído!${NC}"
EOF

chmod +x "$BACKUP_DIR/restore.sh"

log_info "Script de restore criado: $BACKUP_DIR/restore.sh"
echo ""

# Instrução para próximo passo
log_warning "════════════════════════════════════════════════════════"
log_warning "Backup concluído! Agora você pode deletar os buckets com segurança."
log_warning ""
log_warning "Para deletar os buckets:"
log_warning "  ./delete_all_s3_buckets.sh"
log_warning ""
log_warning "Para restaurar os buckets (se necessário):"
log_warning "  cd $BACKUP_DIR && ./restore.sh"
log_warning "════════════════════════════════════════════════════════"
