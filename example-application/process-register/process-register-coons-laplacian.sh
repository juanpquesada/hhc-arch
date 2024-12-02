#!/bin/bash

echo "Processes to register:"
echo "   coons"
echo "   laplacian"
echo ""

# Store authentication data and the API id in variables
api_id='<API_GATEWAY_API_ID>'
client_id='<AWS_CLIENT_ID>'
password='<PASSWORD>'
user='<USER>'

# Get the authorization token (id token) for the user
id_token=$(aws cognito-idp initiate-auth \
	--auth-flow USER_PASSWORD_AUTH \
	--auth-parameters USERNAME=$user,PASSWORD=$password \
	--client-id $client_id \
	| jq '.AuthenticationResult.IdToken')
len=$((${#id_token}-2))
id_token=${id_token:1:$len}
 
# Send the tasks (invoking the action created in the API)
curl \
	--header "Authorization: $id_token" \
	--header 'Content-Type: application/json' \
	--location \
	--request POST "https://$api_id.execute-api.us-east-1.amazonaws.com/prod/send-task" \
	--data @- << EOF
{
	"type": "process-register",
	"register": {
		"deployedProcess": {
		  "name": "coons",
		  "description": "Coons Patch",
		  "input": "{\"parametricData\" => (String -S3 Object URL-), \"boundaryData\" => (String -S3 Object URL-)}",
		  "output": "{\"mesh2D\" => (String -S3 Object URL-), \"numTangledNodes\" => (String -S3 Object URL-)}",
		  "cloudProvider": "os"
	    }
	}
}
EOF

echo ""
echo ""

curl \
	--header "Authorization: $id_token" \
	--header 'Content-Type: application/json' \
	--location \
	--request POST "https://$api_id.execute-api.us-east-1.amazonaws.com/prod/send-task" \
	--data @- << EOF
{
	"type": "process-register",
	"register": {
		"deployedProcess": {
		  "name": "laplacian",
		  "description": "Laplacian Processing",
		  "input": "{\"parametricData\" => (String -S3 Object URL-), \"boundaryData\" => (String -S3 Object URL-), \"epsilon\" => (Float), \"maxIter\" => (Integer)}",
		  "output": "{\"mesh2D\" => (String -S3 Object URL-), \"numTangledNodes\" => (String -S3 Object URL-)}",
		  "cloudProvider": "azure"
	    }
	}
}
EOF