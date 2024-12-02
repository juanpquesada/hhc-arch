#!/bin/bash

# Delete the resource stack
aws cloudformation delete-stack --stack-name stack-hhcarch

# Delete the S3 buckets
aws s3 rb s3://hhcarch-bucket --force > /dev/null
aws s3 rb s3://lambda-functions-hhcarch --force > /dev/null
