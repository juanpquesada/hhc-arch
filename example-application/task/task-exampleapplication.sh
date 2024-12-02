#!/bin/bash

# Upload data required by the task to the S3 bucket
python3 ~/Desktop/hhc-arch/example-application/task/upload_data.py

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
 
# Send the task (invoking the action created in the API)
# num_nodes = (64+1) * (64+1) = 4225
curl \
    --data '{ "type": "task", "task": { "name": "taskexampleapplication", "procs": [ { "id": 1, "name": "coons", "params": {"parametricData": "http://s3.amazonaws.com/<BUCKET>/tangled-parametric.msh", "boundaryData": "http://s3.amazonaws.com/<BUCKET>/tangled-physical.msh"}, "dependsOn": [] }, { "id": 2, "dependsOn": [1], "if": "Float({http://s3.amazonaws.com/<BUCKET>/tanglednodes-taskexampleapplication-p1})/4225 >= 0.01", "then": [ { "id": 3, "name": "laplacian", "params": {"parametricData": "http://s3.amazonaws.com/<BUCKET>/tangled-parametric.msh", "boundaryData": "http://s3.amazonaws.com/<BUCKET>/coons-taskexampleapplication-p1.msh", "epsilon": 0.01, "maxIter": 300}, "dependsOn": [] } ] } ], "outProcs": [1, 3], "notificationEmail": "<EMAIL>" } }' \
	--header "Authorization: $id_token" \
	--header 'Content-Type: application/json' \
	--location \
	--request POST \
    "https://$api_id.execute-api.us-east-1.amazonaws.com/prod/send-task"