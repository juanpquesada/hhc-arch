#!/bin/bash

# Create an empty S3 bucket for storing Lambda function code
exists=$(aws s3 ls | grep lambda-functions-hhcarch)
if [ "$exists" ];
then
  aws s3 rb s3://lambda-functions-hhcarch --force > /dev/null
fi
aws s3 mb s3://lambda-functions-hhcarch > /dev/null

# Get deployment package (ZIP archive) for Lambda function "dispatcher" and upload it to S3
if [ -f ~/Desktop/hhc-arch/aws/dispatcher/dispatcher.zip ];
then
  rm ~/Desktop/hhc-arch/aws/dispatcher/dispatcher.zip
fi
cd ~/Desktop/hhc-arch/aws/dispatcher
if [ -d vendor ];
then
  rm -R vendor
fi
if [ -d docker-image ];
then
  rm -R docker-image
fi
# Required steps to get the .zip deployment package with (Ruby) native libraries
mkdir docker-image
cd docker-image
echo "FROM public.ecr.aws/sam/build-ruby3.2:latest-x86_64" > dockerfile
echo "RUN gem update bundler" >> dockerfile
echo "CMD /bin/bash" >> dockerfile
# The next command is only necessary on macOS in order to run Docker
open -a Docker
docker build -t awsruby32 .
cd ~/Desktop/hhc-arch/aws/dispatcher
docker run --rm -it -v $PWD:/var/task -w /var/task awsruby32 \
	       /bin/bash -c "bundle config set --local path 'vendor/bundle' && bundle install"
zip -r dispatcher.zip lambda_function.rb dispatcher.inc.rb vendor > /dev/null
aws s3 cp ~/Desktop/hhc-arch/aws/dispatcher/dispatcher.zip s3://lambda-functions-hhcarch > /dev/null

# Get deployment package (ZIP archive) for Lambda function "pcm" and upload it to S3
if [ -f ~/Desktop/hhc-arch/aws/pcm/pcm.zip ];
then
  rm ~/Desktop/hhc-arch/aws/pcm/pcm.zip
fi
cd ~/Desktop/hhc-arch/aws/pcm
cp ~/Desktop/hhc-arch/aws/config/config_hhcarch.inc.rb ~/Desktop/hhc-arch/aws/pcm
zip -r pcm.zip lambda_function.rb pcm.inc.rb config_hhcarch.inc.rb > /dev/null
aws s3 cp ~/Desktop/hhc-arch/aws/pcm/pcm.zip s3://lambda-functions-hhcarch > /dev/null

# Create an empty S3 bucket for data and results
exists=$(aws s3 ls | grep hhcarch-bucket)
if [ "$exists" ];
then
  aws s3 rb s3://hhcarch-bucket --force > /dev/null
fi
aws s3api create-bucket \
	--bucket hhcarch-bucket \
    --object-ownership BucketOwnerPreferred > /dev/null
aws s3api delete-public-access-block \
    --bucket hhcarch-bucket

# Create a resource stack
aws cloudformation create-stack --stack-name stack-hhcarch --template-body file://~/Desktop/hhc-arch/aws/cloudformation-hhcarch-aws.json --capabilities CAPABILITY_NAMED_IAM