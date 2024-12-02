# A Hybrid, Heterogeneous Cloud Computing Architecture for Collaborative Environments
In order to deploy all the infrastructure required for HHC-ARCH, and to test it, we must follow the next steps:

    1. Install OpenStack, Kubernetes and OpenFaaS according to the steps listed in the document "OpenStack+Kubernetes+OpenFaaS_Installation.txt" located inside the directory "os".

    2. Create through the AWS Management Console the API that users will use to send their tasks, and create and verify an email address identity that will be used for sending notifications to users. The steps to follow for these actions are listed in the document "deploy-hhcarch-aws" located inside the directory "aws".

    3. Install the AWS CLI, the Azure CLI, the Azure Functions Core Tools, and the OpenStack CLI following the steps listed in the document "AWSCLI+AzureCLI+OpenStackCLI_Installation.txt" located in the root directory.

    4. Execute the script "deploy-hhcarch.sh" located in the root directory.

    5. Execute the script "deploy-example-application.sh" located inside the directory "example-application". To deploy the OpenFaaS function we must connect to the Nova instance via SSH and execute the commands showed as comments in "deployed-example-application.sh".



In order to release all the resources deployed for HHC-ARCH, we must follow the next steps:

    1. Execute the script "release-example-application.sh" located inside the directory "example-application". To delete the OpenFaaS function we must connect to the Nova instance via SSH and execute the commands showed as comments in "release-example-application.sh".

    2. Execute the script "release-hhcarch.sh" located in the root directory.
