#!/bin/bash

### Release of resources deployed in Azure ###
# Login
az login \
	--username <USERNAME>

# Delete deployed resources
az functionapp delete \
    --name <FUNCTIONAPP_NAME \
	--resource-group <RESOURCE_GROUP_NAME>

az storage queue delete \
    --account-name <STORAGE_ACCOUNT_NAME> \
    --name laplacian-queue-azure

# Logout
az logout

### Release of resources deployed in OpenStack ###
# Load credentials
#source ~/Desktop/hhc-arch/os/<OS_PROJECT_NAME>-openrc.sh

# Delete deployed resources
#openstack messaging subscription delete coons-queue-os <subscription_id>

# (commands to run directly in the instance where OpenFaaS is installed)
#cd ~/hhc-arch/os/procs/coons
#faas-cli rm coons

#openstack messaging queue delete coons-queue-os