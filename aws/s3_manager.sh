#!/bin/bash

# Menu Principal - Gerenciamento de Buckets S3
# Script centralizador para todas as operações

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear

# Banner
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║       Gerenciamento de Buckets S3 - AWS                  ║
║                                                           ║
║       Ferramentas para análise, backup e deleção         ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verifica AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}[ERRO]${NC} AWS CLI não está instalado!"
    echo "Instale com: pip install awscli"
    exit 1
fi

# Verifica credenciais
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}[ERRO]${NC} Credenciais AWS não configuradas!"
    echo "Configure com: aws configure"
    exit 1
fi

# Mostra conta atual
echo -e "${GREEN}Conta AWS ativa:${NC}"
account_info=$(aws sts get-caller-identity)
account_id=$(echo "$account_info" | jq -r '.Account' 2>/dev/null || echo "N/A")
user_arn=$(echo "$account_info" | jq -r '.Arn' 2>/dev/null || echo "N/A")

echo -e "  ${BLUE}Account ID:${NC} $account_id"
echo -e "  ${BLUE}User ARN:${NC} $user_arn"
echo ""

# Conta buckets
bucket_count=$(aws s3 ls | wc -l)
echo -e "${GREEN}Buckets S3 na conta:${NC} $bucket_count"
echo ""

# Menu
while true; do
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Escolha uma opção:${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} 📊 Analisar buckets (DRY-RUN)"
    echo -e "  ${GREEN}[2]${NC} 💾 Fazer backup dos buckets"
    echo -e "  ${GREEN}[3]${NC} 🗑️  Deletar TODOS os buckets (completo)"
    echo -e "  ${GREEN}[4]${NC} ⚡ Deletar TODOS os buckets (rápido)"
    echo -e "  ${GREEN}[5]${NC} 🎯 Deletar buckets específicos (interativo)"
    echo -e "  ${GREEN}[6]${NC} 📋 Listar buckets simples"
    echo -e "  ${GREEN}[7]${NC} ℹ️  Ajuda e documentação"
    echo -e "  ${RED}[0]${NC} 🚪 Sair"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "Opção: " choice
    echo ""
    
    case $choice in
        1)
            echo -e "${BLUE}Executando análise de buckets...${NC}"
            echo ""
            ./analyze_s3_buckets.sh
            ;;
        2)
            echo -e "${BLUE}Iniciando backup dos buckets...${NC}"
            echo ""
            ./backup_s3_before_delete.sh
            ;;
        3)
            echo -e "${YELLOW}Iniciando deleção COMPLETA de buckets...${NC}"
            echo ""
            ./delete_all_s3_buckets.sh
            ;;
        4)
            echo -e "${YELLOW}Iniciando deleção RÁPIDA de buckets...${NC}"
            echo ""
            ./delete_s3_simple.sh
            ;;
        5)
            echo -e "${BLUE}Modo interativo de deleção...${NC}"
            echo ""
            ./delete_s3_interactive.sh
            ;;
        6)
            echo -e "${GREEN}Listagem de buckets:${NC}"
            echo ""
            aws s3 ls
            ;;
        7)
            echo -e "${CYAN}════════════════════ AJUDA ═══════════════════════${NC}"
            echo ""
            echo -e "${BOLD}Opção 1 - Analisar buckets${NC}"
            echo "  • Lista todos os buckets"
            echo "  • Mostra quantidade de objetos e tamanho"
            echo "  • Verifica versionamento"
            echo "  • NÃO deleta nada (seguro)"
            echo ""
            echo -e "${BOLD}Opção 2 - Fazer backup${NC}"
            echo "  • Cria backup completo dos buckets"
            echo "  • Salva objetos e metadados"
            echo "  • Cria script de restore"
            echo "  • Recomendado antes de deletar"
            echo ""
            echo -e "${BOLD}Opção 3 - Deletar completo${NC}"
            echo "  • Script robusto com logging detalhado"
            echo "  • Remove objetos versionados"
            echo "  • Confirmação obrigatória (DELETE-ALL)"
            echo "  • Resumo da operação"
            echo ""
            echo -e "${BOLD}Opção 4 - Deletar rápido${NC}"
            echo "  • Versão minimalista"
            echo "  • Execução mais rápida"
            echo "  • Confirmação simples (SIM)"
            echo ""
            echo -e "${BOLD}Opção 5 - Deletar interativo${NC}"
            echo "  • Seleciona buckets específicos"
            echo "  • Confirmação dupla"
            echo "  • Mais controle sobre o que deletar"
            echo ""
            echo -e "${BOLD}Opção 6 - Listar simples${NC}"
            echo "  • Lista rápida dos buckets"
            echo "  • Comando AWS CLI direto"
            echo ""
            echo -e "${RED}⚠️  ATENÇÃO:${NC} Todas as opções de deleção são"
            echo "    IRREVERSÍVEIS! Use com cuidado!"
            echo ""
            echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
            ;;
        0)
            echo -e "${GREEN}Saindo...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opção inválida!${NC}"
            ;;
    esac
    
    echo ""
    echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
    read
    clear
    
    # Atualiza contagem de buckets
    bucket_count=$(aws s3 ls | wc -l)
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║       Gerenciamento de Buckets S3 - AWS                  ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${GREEN}Conta AWS:${NC} $account_id"
    echo -e "${GREEN}Buckets S3:${NC} $bucket_count"
    echo ""
done
