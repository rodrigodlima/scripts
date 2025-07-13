#!/bin/bash

echo "| Subscription ID | Container App Name | Resource Group | Location |"
echo "|------------------|--------------------|----------------|----------|"

# Lista todas as subscriptions que o usuário tem acesso
subs=$(az account list --query "[].id" -o tsv)

for sub in $subs; do
  az account set --subscription "$sub"

  # Lista os Container Apps e formata para Markdown
  az containerapp list --query "[].{name:name, rg:resourceGroup, location:location}" -o tsv | while IFS=$'\t' read -r name rg location; do
    echo "| $sub | $name | $rg | $location |"
  done
done

