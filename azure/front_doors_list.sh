#!/bin/bash

echo "| Subscription ID | Front Door Name | Resource Group | Location |"
echo "|------------------|--------------------|----------------|----------|"

# Lista todas as subscriptions que o usuário tem acesso
subs=$(az account list --query "[].id" -o tsv)

for sub in $subs; do
  az account set --subscription "$sub" >/dev/null 2>&1

  # Captura saída do comando em uma variável
  front_doors=$(az afd profile list --query "[].{name:name, rg:resourceGroup, location:location}" -o tsv 2>/dev/null)

  # Verifica se a variável está vazia
  if [[ -n "$front_doors" ]]; then
    while IFS=$'\t' read -r name rg location; do
      echo "| $sub | $name | $rg | $location |"
    done <<< "$front_doors"
  fi
done

