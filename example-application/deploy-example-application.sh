#!/bin/bash

### Deployment in Azure ###
# Login
az login \
	--username <USERNAME>

# Create the queue used by the process (function)
az storage queue create \
    --account-name <ACCOUNT_NAME> \
    --name laplacian-queue-azure

# Publish the function
az functionapp create \
    --consumption-plan-location westeurope \
    --functions-version 4 \
    --name <FUNCTIONAPP_NAME> \
    --os-type Linux \
    --resource-group <RESOURCE_GROUP_NAME> \
    --runtime python \
    --runtime-version 3.11 \
    --storage-account <STORAGE_ACCOUNT_NAME>
sleep 2m

cd ~/Desktop/hhc-arch/example-application/procs/laplacian-azure
func azure functionapp publish <FUNCTIONAPP_NAME>

# Logout
az logout

### Deployment in OpenStack ###
# Load credentials
#source ~/Desktop/hhc-arch/os/<OS_PROJECT_NAME>-openrc.sh

# Create the queue used by the process (function)
#openstack messaging queue create coons-queue-os

# Deploy the function
# (commands to run directly in the instance where OpenFaaS is installed)
#cd ~/hhc-arch/os/procs/coons
#faas-cli deploy -f ./coons.yml

# Create a subscription for the function to the queue
#openstack messaging subscription create coons-queue-os http://<FLOATING_IP>:8080/async-function/coons 31536000

### Registration of processes (the functions) ###
~/Desktop/hhc-arch/example-application/process-register/process-register-coons-laplacian.sh