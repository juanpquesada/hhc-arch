#!/bin/bash

echo "Releasing HHC-ARCH..."

echo "Releasing resources in OpenStack...(1/3)"
echo "Actually, the deployed resources must be released manually"
#~/Desktop/hhc-arch/os/release-hhcarch-os.sh

echo "Releasing resources in AWS...(2/3)"
~/Desktop/hhc-arch/aws/release-hhcarch-aws.sh

echo "Releasing resources in Azure...(3/3)"
~/Desktop/hhc-arch/azure/release-hhcarch-azure.sh

sleep 2m
echo "Done"

