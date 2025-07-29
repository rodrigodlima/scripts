#!/bin/bash

# Variáveis
LOCATION="eastus2"
ACR_SUBSCRIPTION="signature-Azure-Administracao"
APP_SUBSCRIPTION="SUBS-AGILINM-DEV"
ACR_NAME="fiergs"
MYSQL_SERVER_NAME="mysql-agilinm-poc"
MYSQL_ADMIN_USER="sqladmin"
MYSQL_ADMIN_PASSWORD="SuaSenhaSegura123!"
STORAGE_ACCOUNT_NAME="staprdstgsenaiagilinmprd"
STORAGE_ACCOUNT_KEY="qmIEui5q7HvJdpPO9+06hQoDqzzc6IBs26xQgkJOVY6ce7dlwGeAMnKu0ZoFpNiQ+CiULVq6DMMk+AStmCZJbA=="

# Garantir que estamos na subscription correta
az account set --subscription "$APP_SUBSCRIPTION"

# Criar Resource Group
az group create --name rg-agilinm-poc --location $LOCATION

# Criar VNet principal
az network vnet create \
  --resource-group rg-agilinm-poc \
  --name vnet-agilinm-poc \
  --address-prefix 172.16.0.0/16 \
  --location $LOCATION

# Subnet para Container Apps (DEVE ser /23 e COM delegação)
az network vnet subnet create \
  --resource-group rg-agilinm-poc \
  --vnet-name vnet-agilinm-poc \
  --name container-apps-subnet \
  --address-prefixes 172.16.0.0/23 \
  --delegations Microsoft.App/environments 

# Subnet para Private Endpoint (SEM delegação)
az network vnet subnet create \
  --resource-group rg-agilinm-poc \
  --vnet-name vnet-agilinm-poc \
  --name private-endpoint-subnet \
  --address-prefixes 172.16.2.0/24

# ============================================================================
# MYSQL COM PRIVATE LINK (não VNet integration)
# ============================================================================

# Criar MySQL Flexible Server SEM integração VNet (público inicialmente)
az mysql flexible-server create \
  --resource-group rg-agilinm-poc \
  --name "$MYSQL_SERVER_NAME" \
  --location $LOCATION \
  --admin-user "$MYSQL_ADMIN_USER" \
  --admin-password "$MYSQL_ADMIN_PASSWORD" \
  --sku-name Standard_D4ads_v5 \
  --tier GeneralPurpose \
  --storage-size 32 \
  --version 8.0.21 \
  --public-access None \
  --subscription "$APP_SUBSCRIPTION"

# Aguardar provisioning do MySQL
echo "Aguardando MySQL ser provisionado..."
az mysql flexible-server wait \
  --resource-group rg-agilinm-poc \
  --name "$MYSQL_SERVER_NAME" \
  --exists

# Criar Private DNS Zone para MySQL
PRIVATE_DNS_ZONE="privatelink.mysql.database.azure.com"

az network private-dns zone create \
  --resource-group rg-agilinm-poc \
  --name "$PRIVATE_DNS_ZONE"

# Link da Private DNS Zone com a VNet
az network private-dns link vnet create \
  --resource-group rg-agilinm-poc \
  --zone-name "$PRIVATE_DNS_ZONE" \
  --name mysql-dns-link \
  --virtual-network vnet-agilinm-poc \
  --registration-enabled false

# Obter resource ID do MySQL Server
MYSQL_RESOURCE_ID=$(az mysql flexible-server show \
  --resource-group rg-agilinm-poc \
  --name "$MYSQL_SERVER_NAME" \
  --query "id" \
  --output tsv)

# Criar Private Endpoint para MySQL
az network private-endpoint create \
  --resource-group rg-agilinm-poc \
  --name pe-mysql-agilinm-poc \
  --vnet-name vnet-agilinm-poc \
  --subnet private-endpoint-subnet \
  --private-connection-resource-id "$MYSQL_RESOURCE_ID" \
  --group-id mysqlServer \
  --connection-name mysql-connection \
  --location $LOCATION

# Criar registro DNS no Private DNS Zone
# Obter IP privado do Private Endpoint
PRIVATE_IP=$(az network private-endpoint show \
  --resource-group rg-agilinm-poc \
  --name pe-mysql-agilinm-poc \
  --query "customDnsConfigs[0].ipAddresses[0]" \
  --output tsv)

# Criar registro A no Private DNS Zone
az network private-dns record-set a create \
  --resource-group rg-agilinm-poc \
  --zone-name "$PRIVATE_DNS_ZONE" \
  --name "$MYSQL_SERVER_NAME"

az network private-dns record-set a add-record \
  --resource-group rg-agilinm-poc \
  --zone-name "$PRIVATE_DNS_ZONE" \
  --record-set-name "$MYSQL_SERVER_NAME" \
  --ipv4-address "$PRIVATE_IP"

# ============================================================================
# CONTAINER APPS
# ============================================================================

# Obter resource ID da subnet para Container Apps
SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-agilinm-poc \
  --vnet-name vnet-agilinm-poc \
  --name container-apps-subnet \
  --query "id" \
  --output tsv)

# Criar environment do Container Apps
az containerapp env create \
  --name env-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --infrastructure-subnet-resource-id "$SUBNET_ID" \
  --internal-only false

# Criar user-assigned managed identity
az identity create \
  --resource-group rg-agilinm-poc \
  --name containerapp-identity

# Obter dados da identity
IDENTITY_ID=$(az identity show \
  --resource-group rg-agilinm-poc \
  --name containerapp-identity \
  --query "id" \
  --output tsv)

IDENTITY_CLIENT_ID=$(az identity show \
  --resource-group rg-agilinm-poc \
  --name containerapp-identity \
  --query "clientId" \
  --output tsv)

IDENTITY_PRINCIPAL_ID=$(az identity show \
  --resource-group rg-agilinm-poc \
  --name containerapp-identity \
  --query "principalId" \
  --output tsv)

# Atribuir identity ao environment
az containerapp env identity assign \
  --name env-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --user-assigned "$IDENTITY_ID"

# ============================================================================
# ACR CONFIGURATION
# ============================================================================

az account set --subscription "$ACR_SUBSCRIPTION"

ACR_ID=$(az acr show --name "$ACR_NAME" --query "id" --output tsv)

az role assignment create \
  --assignee "$IDENTITY_PRINCIPAL_ID" \
  --role AcrPull \
  --scope "$ACR_ID"

# Voltar para subscription da aplicação
az account set --subscription "$APP_SUBSCRIPTION"

# ============================================================================
# STORAGE CONFIGURATION
# ============================================================================

az containerapp env storage set \
  --name env-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --storage-name dotenv-storage \
  --azure-file-account-name "$STORAGE_ACCOUNT_NAME" \
  --azure-file-account-key "$STORAGE_ACCOUNT_KEY" \
  --azure-file-share-name staprdstgsenaiagilinmprd \
  --access-mode ReadWrite

# ============================================================================
# DEPLOY CONTAINER APP
# ============================================================================

# Criar o Container App
az containerapp create \
  --name app-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --environment env-agilinm-poc \
  --yaml config.yaml

# ============================================================================
# VERIFICAÇÕES E TESTE
# ============================================================================

echo "=== VERIFICAÇÕES ==="

echo "1. MySQL Server status:"
az mysql flexible-server show \
  --resource-group rg-agilinm-poc \
  --name "$MYSQL_SERVER_NAME" \
  --query "state" \
  --output tsv

echo "2. Private Endpoint status:"
az network private-endpoint show \
  --resource-group rg-agilinm-poc \
  --name pe-mysql-agilinm-poc \
  --query "provisioningState" \
  --output tsv

echo "3. Private DNS Zone records:"
az network private-dns record-set list \
  --resource-group rg-agilinm-poc \
  --zone-name "$PRIVATE_DNS_ZONE" \
  --output table

echo "4. Container App status:"
az containerapp show \
  --name app-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --query "properties.provisioningState" \
  --output tsv

echo "5. Private IP do MySQL:"
echo "$PRIVATE_IP"

echo "=== INFORMAÇÕES DE CONEXÃO ==="
echo "Host: ${MYSQL_SERVER_NAME}.privatelink.mysql.database.azure.com"
echo "Private IP: $PRIVATE_IP"
echo "Port: 3306"
echo "Database: [seu_database]"
echo "User: ${MYSQL_ADMIN_USER}"
echo "Password: [usar variável de ambiente segura]"

echo "=== TESTE DE CONECTIVIDADE ==="
echo "Para testar dentro do Container App, use:"
echo "nslookup ${MYSQL_SERVER_NAME}.privatelink.mysql.database.azure.com"
echo "telnet ${MYSQL_SERVER_NAME}.privatelink.mysql.database.azure.com 3306"