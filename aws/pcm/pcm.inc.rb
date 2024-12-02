#
# hhc-arch/aws/pcm/pcm.inc.rb
#
# This file is required by hhc-arch/aws/pcm/lambda_function.rb.
# It defines some constant values and some useful functions:
#    deploy_process(proc_name, s3_bucket, s3_key)
#    procname_available(proc_name)
#    register_process(reg_data)
#
require 'aws-sdk'

# AWS
DYNAMODB_TABLE_CATALOG = 'catalog'
LAMBDA_EXECUTION_ROLE  = 'LambdaExecutionRole'

# Function that deploys the necessary resources to make the process available
# (currently, only for processes as AWS Lambda functions)
def deploy_process(proc_name, s3_bucket, s3_key)
  # Create the queue
  sqs = Aws::SQS::Client.new
  params = {
    queue_name: "#{proc_name}-queue-aws",
    attributes: {
      "VisibilityTimeout" => "300"
    }
  }
  queue = sqs.create_queue(params)

  # Create the Lambda function
  iam = Aws::IAM::Client.new
  execution_role = iam.get_role(role_name: LAMBDA_EXECUTION_ROLE)
  lambda = Aws::Lambda::Client.new
  params = {
    code: {
      s3_bucket: s3_bucket,
      s3_key: s3_key
    },
    function_name: proc_name,
    handler: "lambda_function.lambda_handler",
    publish: true,
    role: execution_role.role.arn,
    runtime: "ruby3.2",
    timeout: 300
  }
  lambda_function = lambda.create_function(params)

  # Create the event source mapping
  params = {
    queue_url: queue.queue_url,
    attribute_names: [ 'QueueArn' ]
  }
  resp = sqs.get_queue_attributes(params)
  params = {
    batch_size: 10,
    enabled: true,
    event_source_arn: resp.attributes['QueueArn'],
    function_name: proc_name
  }
  esm = lambda.create_event_source_mapping(params)
end

# Function that returns if a process name is available or not, since
# the process name must be unique
def procname_available(proc_name)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      procName: proc_name
    },
    table_name: DYNAMODB_TABLE_CATALOG
  }
  resp = dynamodb.get_item(params)
  if (!resp.item.nil?)
    return false
  end

  return true
end

# Function that updates the process catalog with a new process
def register_process(reg_data)
  item = {}
  if (reg_data.key?('deployedProcess'))
    proc_name = reg_data['deployedProcess']['name']
    if (procname_available(proc_name))
      item = {
        'procName' => proc_name,
        'description' => reg_data['deployedProcess']['description'],
        'input' => reg_data['deployedProcess']['input'],
        'output' => reg_data['deployedProcess']['output'],
        'cloudProvider' => reg_data['deployedProcess']['cloudProvider'],
        'state' => 'AVAILABLE'
      }
    end
  elsif (reg_data.key?('toBeDeployedProcess'))
    proc_name = reg_data['toBeDeployedProcess']['name']
    if (procname_available(proc_name))
      s3_bucket = reg_data['toBeDeployedProcess']['code']['S3Bucket']
      s3_key = reg_data['toBeDeployedProcess']['code']['S3Key']
      deploy_process(proc_name, s3_bucket, s3_key)
      item = {
        'procName' => proc_name,
        'description' => reg_data['toBeDeployedProcess']['description'],
        'input' => reg_data['toBeDeployedProcess']['input'],
        'output' => reg_data['toBeDeployedProcess']['output'],
        'cloudProvider' => 'aws',
        'state' => 'AVAILABLE'
      }
    end
  end
  if (!item.empty?)
    dynamodb = Aws::DynamoDB::Client.new
    params = {
      item: item,
      table_name: DYNAMODB_TABLE_CATALOG
    }
    resp = dynamodb.put_item(params)
  end
end
