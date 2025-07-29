#!/bin/bash

# Variáveis

LOCATION="eastus2"
ACR_SUBSCRIPTION="signature-Azure-Administracao"
ACR_NAME="fiergs"
MYSQL_SERVER_NAME="mysql-agilinm-poc"
MYSQL_ADMIN_USER="sqladmin"
MYSQL_ADMIN_PASSWORD="SuaSenhaSegura123!"
STORAGE_ACCOUNT_NAME="staprdstgsenaiagilinmprd"
STORAGE_ACCOUNT_KEY="qmIEui5q7HvJdpPO9+06hQoDqzzc6IBs26xQgkJOVY6ce7dlwGeAMnKu0ZoFpNiQ+CiULVq6DMMk+AStmCZJbA=="


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
 # Subnet para MySQL Flexible Server (COM delegação específica)
 az network vnet subnet create \
   --resource-group rg-agilinm-poc \
   --vnet-name vnet-agilinm-poc \
   --name mysql-subnet \
   --address-prefixes 172.16.3.0/24 \
   --delegations Microsoft.DBforMySQL/flexibleServers


# Criar MySQL Flexible Server com integração VNet

# OBS: Talvez esse comando não funcione com o Azure CLI na versão 2.0.75, pois aparentemente é um bug da API do Azure. Se falhar, atualize o Azure CLI para a versão mais recente.

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
  --vnet vnet-agilinm-poc \
  --subnet mysql-subnet \
  --private-dns-zone "$MYSQL_SERVER_NAME.private.mysql.database.azure.com" \
  --subscription "SUBS-AGILINM-DEV"

# Obter resource ID da subnet
SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-agilinm-poc \
  --vnet-name vnet-agilinm-poc \
  --name container-apps-subnet \
  --query "id" \
  --output tsv)

# Criar environment
az containerapp env create \
  --name env-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --infrastructure-subnet-resource-id "$SUBNET_ID" \
  --internal-only false

# Permitir acesso apenas da VNet (já configurado automaticamente)
# Verificar regras de firewall
az mysql flexible-server firewall-rule list \
  --resource-group rg-agilinm-poc \
  --name "$MYSQL_SERVER_NAME" \
  --output table

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

az containerapp env identity assign \
  --name env-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --user-assigned /subscriptions/90d2fc37-8f87-4938-ab37-060c2b839604/resourcegroups/rg-agilinm-poc/providers/Microsoft.ManagedIdentity/userAssignedIdentities/containerapp-identity

# Mudar para subscription do ACR
az account set --subscription "$ACR_SUBSCRIPTION"

# Obter resource ID do ACR
ACR_ID=$(az acr show --name "$ACR_NAME" --query "id" --output tsv)

# Dar permissão AcrPull para a managed identity
az role assignment create \
  --assignee "$IDENTITY_PRINCIPAL_ID" \
  --role AcrPull \
  --scope "$ACR_ID"

# Voltar para subscription da aplicação
az account set --subscription "$APP_SUBSCRIPTION"


# Configurar armazenamento para environment
# OBS: O nome do storage deve ser único globalmente, então use um nome exclusivo para sua conta de armazenamento.
az containerapp env storage set \
  --name env-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --storage-name dotenv-storage \
  --azure-file-account-name "staprdstgsenaiagilinmprd" \
  --azure-file-account-key "qmIEui5q7HvJdpPO9+06hQoDqzzc6IBs26xQgkJOVY6ce7dlwGeAMnKu0ZoFpNiQ+CiULVq6DMMk+AStmCZJbA==" \
  --azure-file-share-name staprdstgsenaiagilinmprd \
  --access-mode ReadWrite

az containerapp create \
  --name app-agilinm-poc \
  --resource-group rg-agilinm-poc \
  --environment env-agilinm-poc \
  --yaml config.yaml

az network private-dns link vnet create \
  --resource-group rg-agilinm-poc \
  --zone-name mysql-agilinm-poc.private.mysql.database.azure.com \
  --name mysql-dns-link \
  --virtual-network vnet-agilinm-poc \
  --registration-enabled false