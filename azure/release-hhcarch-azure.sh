#!/bin/bash

# Login
az login \
	--username <USERNAME>

# Delete deployed resources
az group delete \
	--name <RESOURCE_GROUP_NAME>

# Logout
az logout