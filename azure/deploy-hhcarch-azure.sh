#!/bin/bash

# Login
az login \
	--username <USERNAME>

# Create a resource group
az group create \
    --location westeurope \
    --name <RESOURCE_GROUP_NAME>

# Create a storage account
az storage account create \
    --location westeurope \
    --name <STORAGE_ACCOUNT_NAME> \
    --resource-group <RESOURCE_GROUP_NAME> \
    --sku Standard_LRS

# Get the access key for the storage account
ACCESS_KEY=$(az storage account keys list \
	--account-name <STORAGE_ACCOUNT_NAME> \
    --resource-group <RESOURCE_GROUP_NAME> \
	| jq '.[0].value')
len=$((${#ACCESS_KEY}-2))
ACCESS_KEY=${ACCESS_KEY:1:$len}
sed -i '' \
	"s|AZURE_STORAGE_ACCESS_KEY = '.*'|AZURE_STORAGE_ACCESS_KEY = '${ACCESS_KEY}'|g" \
	~/Desktop/hhc-arch/aws/dispatcher/dispatcher.inc.rb

# Logout
az logout