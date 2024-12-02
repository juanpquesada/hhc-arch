#
# hhc-arch/aws/pcm/lambda_function.rb
#
require 'pcm.inc'

def lambda_handler(event:, context:)
  # Poll the messages retrieved in every single batch of the Lambda function and
  # carry out the requested operations
  event['Records'].each do |msg|
    message = JSON.parse(msg['body'])
    message_type = message['type']
    if (message_type == 'process-register')
      register_process(message['register'])
    end
  end

  { statusCode: 200, body: JSON.generate('AWS Lambda Function: pcm') }
end
