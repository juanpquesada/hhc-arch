#!/bin/bash
#
# Before deploying the necessary infrastructure, we must create in AWS the API
# that users (developers and providers) will utilize to send their tasks, and
# create and verify an email address identity that the "Dispatcher" will use
# to send notifications to users. The steps to follow for these actions are
# listed below and must be done signing in to the AWS Management Console with
# user "deployer" (belonging to deployers group, as showed in the following
# policies list).
#
# Permission policies:
#    Group "administrators" (user "admin")
#       AdministratorAccess
#    Group "deployers" (user "deployer")
#       AmazonAPIGatewayAdministrator
#       AmazonCognitoPowerUser
#       AmazonDynamoDBFullAccess
#       AmazonS3FullAccess
#       AmazonSESFullAccess (Add this policy after creating and checking the
#                            API, and after removing the
#                            AWSCloudShellFullAccess policy)
#       AmazonSQSFullAccess
#       AWSCloudFormationFullAccess (Customer managed)
#       AWSCloudShellFullAccess (Only for checking the API, after that it is
#                                necessary to remove it)
#       AWSLambdaFullAccess
#       IAMAccessAnalyzerFullAccess
#       IAMFullAccess
#    Group "developers" (user "dev")
#       AmazonCognitoPowerUser
#       AmazonS3FullAccess
#    Group "providers" (user "provider")
#       AmazonCognitoPowerUser
#       AmazonS3FullAccess
#       AWSLambdaFullAccess
#
# 1. Create a standard queue whith name "in-queue" and visibility timeout of 300 seconds.
#
# 2. Create an IAM policy with name "SendTaskPolicy" using the following JSON:
#    {
#       "Version": "2012-10-17",
#       "Statement": [
#          {
#             "Effect": "Allow",
#	          "Action": "sqs:SendMessage",
#	          "Resource": "arn:aws:sqs:us-east-1:<ACCOUNT_ID>:in-queue"
#          }
#       ]
#    }
# 
# 3. Create an IAM role with name "SendTaskRole".
#    3.1. Create the role.
#         Step 1 (Select trusted entity)
#            - Trusted entity type: AWS service
#            - Use case: API Gateway
#         Step 2 (Add permissions)
#            - (Nothing)
#         Step 3 (Name, review, and create)
#            - Role name: SendTaskRole
#    3.2. Click on the role from the list of roles.
#    3.3. Attach policy "SendTaskPolicy" to the role (Add permissions - Attach policies).
#
# 4. Create an API with Amazon API Gateway.
#    4.1. Build a REST API.
#         API details
#            - New API
#            - API name: <API_NAME>
#            - API endpoint type: Regional
#    4.2. Create a resource with name "send-task".
#    4.3. Create a method POST within the resource "send-task".
#         Method details
#            - Method type: POST
#            - Integration type: AWS service
#            - AWS Region: us-east-1
#            - AWS Service: Simple Queue Service (SQS)
#            - HTTP method: POST
#            - Action type: Use path override
#            - Path override: <ACCOUNT_ID>/in-queue
#            - Execution role: arn:aws:iam::<ACCOUNT_ID>:role/SendTaskRole
#    4.4. Click on Integration request - Edit and add a URL request header parameter
#         and a mapping template.
#         URL request headers parameters
#            - Name: Content-Type
#            - Mapped from: 'application/x-www-form-urlencoded'
#         Mapping templates
#            - Content type: application/json
#            - Template body: Action=SendMessage&MessageBody=$input.body
#    4.5. Deploy the API.
#         - Stage: *New stage*
#         - Stage name: prod
#
# 5. Check the API.
#    5.1. Execute the following command, for example in the AWS CloudShell:
#         curl --location --request POST 'https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod/send-task'
#              --header 'Content-Type: application/json' --data-raw '{"message": "This is a sample message."}'
#
# 6. Create a user pool in Amazon Cognito.
#    Step 1 (Configure sign-in experience)
#       Authentication providers
#       - Provider types: Cognito user pool
#       - Cognito user pool sign-in options: Email
#    Step 2 (Configure security requirements)
#       Password policy
#		- Password policy mode: Cognito defaults
#       Multi-factor authentication
#       - MFA enforcement: No MFA
#    Step 3 (Configure sign-up experience)
#       Required attributes
#       - Additional required attributes: family_name, given_name
#    Step 4 (Configure message delivery)
#       Email
#       - Email provider: Send email with Cognito
#    Step 5 (Integrate your app)
#       User pool name
#       - User pool name: <USER_POOL_NAME>
#       Hosted authentication pages
#       - Check the option "Use the Cognito Hosted UI".
#       Domain
#       - Use a Cognito domain
#       - Cognito domain: https://<DOMAIN>(.auth.us-east-1.amazoncognito.com)
#       Initial app client
#       - App type: Public client
#       - App client name: <APP_CLIENT_NAME>
#       - Allowed callback URLs: <CALLBACK_URL>
#       Advanced app client settings
#       - Authentication flows: ALLOW_ADMIN_USER_PASSWORD_AUTH, ALLOW_USER_PASSWORD_AUTH, ALLOW_USER_SRP_AUTH
#    Step 6 (Review and create)
#       - (Nothing)
#
# 7. Create an authorizer in the API <API_NAME>.
#    Authorizers details
#    - Authorizer name: <AUTHORIZER_NAME>
#    - Authorizer type: Cognito
#    - Cognito user pool: <USER_POOL_NAME>
#    - Token source: Authorization
#
# 8. Change the authorization setting of the POST action in the "Method request" of the API to <AUTHORIZER_NAME>
#    and deploy the API again.
#
# 9. Check the integration of Amazon API Gateway, Amazon Cognito and Amazon SQS.
#    9.1. Create a user in the Amazon Cognito user pool created previously
#         (<USER_POOL_NAME> / App integration / <APP_CLIENT_NAME> / View Hosted UI).
#
#    9.3. Get the authorization token (id token) for the user, executing the following command
#         in the AWS CloudShell (CLIENT_ID is the Client ID of the app client created in the user pool):
#         aws cognito-idp initiate-auth --client-id <CLIENT_ID> --auth-flow USER_PASSWORD_AUTH
#                                       --auth-parameters USERNAME=<USER_EMAIL>,PASSWORD=<USER_PASSWORD>
# 
#    9.4. Invoke the action created in the API (that will send a message to the queue).
#     curl --location --request POST 'https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod/send-task'
#          --header 'Content-Type: application/json' --header 'Authorization: <ID_TOKEN>'
#          --data-raw '{"message": "This is a sample message."}'
#
# 10. Create and verify an email address identity through the Amazon SES console.
#
echo "Deploying HHC-ARCH..."

echo "Deploying resources in Azure...(1/3)"
~/Desktop/hhc-arch/azure/deploy-hhcarch-azure.sh
sleep 2m

echo "Deploying resources in AWS...(2/3)"
# credentials and config files must be in ~/.aws
~/Desktop/hhc-arch/aws/deploy-hhcarch-aws.sh
sleep 3m

echo "Deploying resources in OpenStack...(3/3)"
echo "Actually, the required resources must be deployed manually"
#~/Desktop/hhc-arch/os/deploy-hhcarch-os.sh
sleep 1m

echo "Done"
