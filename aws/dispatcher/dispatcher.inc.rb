#
# hhc-arch/aws/dispatcher/dispatcher.inc.rb
#
# This file is required by hhc-arch/aws/dispatcher/lambda_function.rb.
# It defines some constant values and configuration data (including
# credentials) so that the Dispatcher can access to some AWS, Azure and
# OpenStack services. Also, it defines some useful functions:
#    check_condition(condition)
#    dependencies_resolved(task_name, depends_on)
#    get_proc_cloud_provider(proc_name)
#    get_proc_hash(procs, proc_state='WAITING', condition=nil)
#    get_proc_result(task_name, proc_id)
#    get_proc_state(task_name, proc_id)
#    get_procs_to_be_run(task_name)
#    get_task_data(task_name)
#    get_task_state(task_name)
#    initialize_task(task)
#    resend_process_register_message(msg)
#    revert_processes_state_to_initial_values(task_name, forprocess_id)
#    send_notification(task_name, task_state, email)
#    send_process_trigger_message(task_name, proc_id, proc_params, queue_name)
#    send_task_initialization_ack_message(task_name, ack_code, queue_name)
#    send_task_response_message(task_name, task_result, queue_name)
#    task_completed(task_name)
#    taskname_available(task_name)
#    update_num_pending_iterations(task_name, forprocess_id, value)
#    update_num_processes_finished(task_name, process_id, num_type, value)
#    update_proc_result(task_name, proc_id, result)
#    update_proc_state(task_name, proc_id, state)
#    update_task_state(task_name, state)
#
require 'aws-sdk'
require 'azure'
require 'base64'
require 'misty'

# AWS
AWS_REGION             = 'us-east-1'
DYNAMODB_TABLE_CATALOG = 'catalog'
DYNAMODB_TABLE_PROCS   = 'procs'
DYNAMODB_TABLE_TASKS   = 'tasks'
EMAIL_ADDRESS_IDENTITY = '<EMAIL>'
LAMBDA_EXECUTION_ROLE  = 'LambdaExecutionRole'
SQS_QUEUE_PCM          = 'pcm-queue'

# Azure
# The Azure Storage Access Key is updated automatically once the infrastructure required in Azure is deployed.
AZURE_STORAGE_ACCESS_KEY = '<AZURE_STORAGE_ACCESS_KEY>'
AZURE_STORAGE_ACCOUNT    = '<AZURE_STORAGE_ACCOUNT>'

# OpenStack
# OS_CLIENT_ID is a UUID that allows sending messages to the queues created in Zaqar
OS_CLIENT_ID    = '<OS_CLIENT_ID>'
OS_HOST         = '<OS_HOST>'
OS_PASSWORD     = '<OS_PASSWORD>'
OS_PROJECT_NAME = '<OS_PROJECT_NAME>'
OS_USERNAME     = '<OS_USERNAME>'

# Function that evaluates the condition of an 'if relation'
def check_condition(condition)
  exp = condition.gsub(/\{[^\{]+\}/) do |match|
    url = match[1..-2]
    Net::HTTP.get(URI.parse("#{url}"))
  end

  return eval(exp)
end

# Function that returns if a set of proccesses have completed or not
# in order to consider dependencies resolved or not by a calling process
def dependencies_resolved(task_name, depends_on)
  if (depends_on.empty?)
    return true
  end

  depends_on.each do |pid|
    state = get_proc_state(task_name, pid)
    if (state != 'FINISHED')
      return false
    end
  end

  return true
end

# Function thas returns the cloud provider where a process is deployed
def get_proc_cloud_provider(proc_name)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      procName: proc_name
    },
    table_name: DYNAMODB_TABLE_CATALOG
  }
  resp = dynamodb.get_item(params)
  cloud_provider = resp.item['cloudProvider']

  return cloud_provider
end

# Function that converts an array of processes into a hash
def get_proc_hash(procs, proc_state='WAITING', condition=nil, forprocess=nil)
  hash = {}
  procs.each do |p|
    key = 'p'+p['id'].to_s
    if (p.has_key?('if'))
      hash[key] = {
        'dependsOn' => p['dependsOn'],
        'state' => proc_state,
        'condition' => condition,
        'numThenProcesses' => p['then'].count,
        'numThenProcessesFinished' => 0
      }
      hash = hash.merge(get_proc_hash(p['then'], 'BLOCKED', {'ifProcess' => key, 'exp' => p['if'], 'value' => true}))
      if (p.has_key?('else'))
        hash[key]['numElseProcesses'] = p['else'].count
        hash[key]['numElseProcessesFinished'] = 0
        hash = hash.merge(get_proc_hash(p['else'], 'BLOCKED', {'ifProcess' => key, 'exp' => p['if'], 'value' => false}))
      end
    elsif (p.has_key?('for'))
      hash[key] = {
        'dependsOn' => p['dependsOn'],
        'state' => proc_state,
        'condition' => condition,
        'forProcess' => forprocess,
        'do' => p['do'],
        'numIterations' => p['for']['finalValue'] - p['for']['initialValue'] + 1,
        'numPendingIterations' => p['for']['finalValue'] - p['for']['initialValue'] + 1,
        'numProcesses' => p['do'].count,
        'numProcessesFinished' => 0
      }
      hash = hash.merge(get_proc_hash(p['do'], 'WAITING', nil, key))
    else
      cloud_provider = get_proc_cloud_provider(p['name'])
      hash[key] = {
        'name' => p['name'],
        'params' => p['params'],
        'dependsOn' => p['dependsOn'],
        'cloudProvider' => cloud_provider,
        'state' => proc_state,
        'result' => {},
        'condition' => condition,
        'forProcess' => forprocess
      }
    end
  end

  return hash
end

# Function that returns the object corresponding to the result of a
# specific task process
def get_proc_result(task_name, proc_id)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS
  }
  resp = dynamodb.get_item(params)
  procs = resp.item['procs']
  key = 'p'+proc_id.to_s
  if (procs[key].nil?)
    result = {}
  else
    result = procs[key]['result']
  end

  return result
end

# Function that returns the state of a specific task process
def get_proc_state(task_name, proc_id)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS
  }
  resp = dynamodb.get_item(params)
  procs = resp.item['procs']
  key = 'p'+proc_id.to_s
  state = procs[key]['state']

  return state
end

# Function that returns the processes of a task than can be run
def get_procs_to_be_run(task_name)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS
  }
  resp = dynamodb.get_item(params)
  task_procs = resp.item['procs']
  procs_to_be_run = []
  task_procs.each do |k, p|
    if (p['state'] == 'WAITING' || p['state'] == 'BLOCKED')
      depends_on = []
      p['dependsOn'].each do |pid|
        depends_on << pid.to_i
      end
      if (dependencies_resolved(task_name, depends_on))
        # Process that represents an 'if relation' or an 'iteration relation'
        if (!p.has_key?('name'))
          proc_id = k[1..k.length].to_i
          update_proc_state(task_name, proc_id, 'RUNNING')
          next
        end

        # Process within an 'if relation'
        if (!p['condition'].nil?)
          ifprocess_id = p['condition']['ifProcess']
          if (get_proc_state(task_name, ifprocess_id[1..ifprocess_id.length].to_i) == 'RUNNING')
            if (check_condition(p['condition']['exp']) == p['condition']['value'])
              update_proc_state(task_name, k[1..k.length].to_i, 'WAITING')
              proc_to_be_run = {
                'taskName' => task_name,
                'procId' => k[1..k.length].to_i,
                'procName' => p['name'],
                'procParams' => p['params'],
                'procCloudProvider' => p['cloudProvider']
              }
              procs_to_be_run << proc_to_be_run
            end
          end
        else
          proc_to_be_run = {
            'taskName' => task_name,
            'procId' => k[1..k.length].to_i,
            'procName' => p['name'],
            'procParams' => p['params'],
            'procCloudProvider' => p['cloudProvider']
          }
          procs_to_be_run << proc_to_be_run
        end
      end
    end
  end

  return procs_to_be_run
end

# Function that returns data of a task
def get_task_data(task_name)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_TASKS
  }
  resp = dynamodb.get_item(params)

  return resp.item
end

# Function that returns the state of a specific task
def get_task_state(task_name)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_TASKS
  }
  resp = dynamodb.get_item(params)
  state = resp.item['taskState']

  return state
end

# Function that parses a task message, initializes the values for the task
# execution and stores permanently all the associated information
def initialize_task(task)
  if (!taskname_available(task['name']))
    msg = 'There is already a task with the same name.'
    return -1, msg
  end

  dynamodb = Aws::DynamoDB::Client.new
  # DYNAMODB_TABLE_TASKS
  item = {
    'taskName' => task['name'],
    'outProcs' => task['outProcs'],
    'notificationEmail' => task['notificationEmail'],
    'taskState' => 'RUNNING'
  }
  params = {
    item: item,
    table_name: DYNAMODB_TABLE_TASKS
  }
  begin
    resp = dynamodb.put_item(params)
  rescue
    return -1, 'Error while initializing the task.'
  end
  # DYNAMODB_TABLE_PROCS
  hash = get_proc_hash(task['procs'])
  item = {
    'taskName' => task['name'],
    'procs' => hash
  }
  params = {
    item: item,
    table_name: DYNAMODB_TABLE_PROCS
  }
  begin
    resp = dynamodb.put_item(params)
  rescue
    return -1, 'Error while initializing the task.'
  end

  msg = 'Task initialized correctly.'
  return 0, msg
end

# Function that forwards a process register message to the PCM
def resend_process_register_message(msg)
  sqs = Aws::SQS::Client.new
  queue_url = sqs.get_queue_url(queue_name: SQS_QUEUE_PCM).queue_url
  resp = sqs.send_message(queue_url: queue_url, message_body: msg)
end

# Function that reverts the state of the processes in an 'iteration relation'
# to their initial values
def revert_processes_state_to_initial_values(task_name, forprocess_id)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS
  }
  resp = dynamodb.get_item(params)
  task_procs = resp.item['procs']
  forprocess = task_procs[forprocess_id]
  hash = get_proc_hash(forprocess['do'], 'WAITING', nil, forprocess_id)
  hash.each do |k, p|
    proc_id = k[1..k.length].to_f
    proc_id = proc_id.to_i
    update_proc_state(task_name, proc_id, p['state'])
  end
end

# Function that sends a notification to a user
def send_notification(task_name, task_state, email)
  # Create a new SES resource
  ses = Aws::SES::Client.new(region: AWS_REGION)

  if (task_state == 'RUNNING')
    begin
      params = {
        destination: {
          to_addresses: [ email ]
        },
        message: {
          body: {
            text: {
              charset: 'UTF-8',
              data: 'Your task "' + task_name + '" has been initialized.'\
                    'You\'ll receive another email when it\'s completed.'
            }
          },
          subject: {
            charset: 'UTF-8',
            data: '[HHC-ARCH] Task: ' + task_name
          }
        },
        source: EMAIL_ADDRESS_IDENTITY
      }
      resp = ses.send_email(params)
    rescue Aws::SES::Errors::ServiceError => error
      puts "Email not sent. Error message: #{error}."
    end
  elsif (task_state == 'FINISHED')
    begin
      params = {
        destination: {
          to_addresses: [ email ]
        },
        message: {
          body: {
            text: {
              charset: 'UTF-8',
              data: 'Your task "' + task_name + '" has completed successfully.'\
                    'From this moment you can access to its results.'
            }
          },
          subject: {
            charset: 'UTF-8',
            data: '[HHC-ARCH] Task: ' + task_name
          }
        },
        source: EMAIL_ADDRESS_IDENTITY
      }
      resp = ses.send_email(params)
    rescue Aws::SES::Errors::ServiceError => error
      puts "Email not sent. Error message: #{error}."
    end
  end
end

# Function that sends a process trigger message
def send_process_trigger_message(task_name, proc_id, proc_params, queue_name)
  process_trigger_message = {
    type: 'process-trigger',
    trigger: {
      taskName: task_name,
      procId: proc_id,
      params: proc_params
    }
  }.to_json
  tokens = queue_name.split('-')
  if (tokens[2] == "aws")
    # AWS Lambda Function
    sqs = Aws::SQS::Client.new
    queue_url = sqs.get_queue_url(queue_name: queue_name).queue_url
    resp = sqs.send_message(queue_url: queue_url, message_body: process_trigger_message)
  elsif (tokens[2] == "azure")
    # Azure Function
    Azure.config.storage_account_name = AZURE_STORAGE_ACCOUNT
    Azure.config.storage_access_key = AZURE_STORAGE_ACCESS_KEY
    azure_queue_service = Azure::Queue::QueueService.new
    process_trigger_message = Base64.encode64(process_trigger_message)
    options = {
      encode: false
    }
    azure_queue_service.create_message(queue_name, process_trigger_message, options)
  elsif (tokens[2] == "os")
    # OpenFaaS Funtion (OpenStack)
    cloud = Misty::Cloud.new(
      :auth => {
        :url               => "http://#{OS_HOST}/identity",
        :user              => OS_USERNAME,
        :password          => OS_PASSWORD,
        :project           => OS_PROJECT_NAME
      },
      :messaging => {
        :endpoint => "http://#{OS_HOST}:8888",
        :headers  => { 'Client-ID' => OS_CLIENT_ID }
      }
    )
    resp = cloud.messaging.post_message(queue_name, '{"messages": [{"body": ' + process_trigger_message + ', "ttl": 900}]}')
  end
end

# Function that sends a task initialization ack message
def send_task_initialization_ack_message(task_name, ack_code, ack_msg, queue_name)
  sqs = Aws::SQS::Client.new
  queue_url = sqs.get_queue_url(queue_name: queue_name).queue_url
  task_initialization_ack_message = {
    type: 'task-initialization-ack',
    ack: {
      taskName: task_name,
      code: ack_code,
      msg: ack_msg
    }
  }.to_json
  resp = sqs.send_message(queue_url: queue_url, message_body: task_initialization_ack_message)
end

# Function that sends a task response message
def send_task_response_message(task_name, task_result, queue_name)
  sqs = Aws::SQS::Client.new
  queue_url = sqs.get_queue_url(queue_name: queue_name).queue_url
  task_response_message = {
    type: 'task-response',
    response: {
      taskName: task_name,
      results: task_result
    }
  }.to_json
  resp = sqs.send_message(queue_url: queue_url, message_body: task_response_message)
end

# Function that returns if a task has completed or not
def task_completed(task_name)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS
  }
  resp = dynamodb.get_item(params)
  task_procs = resp.item['procs']
  task_procs.each do |k, p|
    proc_id = k[1..k.length].to_i
    proc_state = get_proc_state(task_name, proc_id)
    if (proc_state != 'FINISHED' && proc_state != 'BLOCKED')
      return false
    end
  end

  return true
end

# Function that returns if a task name is available or not, since
# the task name must be unique
def taskname_available(task_name)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_TASKS
  }
  resp = dynamodb.get_item(params)
  if (!resp.item.nil?)
    return false
  end

  return true
end

# Function that updates the number of pending iterations
# in a process representing an 'iteration relation'
def update_num_pending_iterations(task_name, forprocess_id, value)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS,
    update_expression: "SET procs.#PID.#NUMITERATIONS = :n",
    expression_attribute_names: {
      "#PID" => "#{forprocess_id}",
      "#NUMITERATIONS" => "numPendingIterations"
    },
    expression_attribute_values: {
      ':n' => value
    }
  }
  resp = dynamodb.update_item(params)
end

# Function that updates the number of processes finished
# in a process representing an 'if relation' or in a process
# representing an 'iteration relation'
def update_num_processes_finished(task_name, process_id, num_type, value)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS,
    update_expression: "SET procs.#PID.#NUMPROCESSES = :n",
    expression_attribute_names: {
      "#PID" => "#{process_id}",
      "#NUMPROCESSES" => "#{num_type}"
    },
    expression_attribute_values: {
      ':n' => value
    }
  }
  resp = dynamodb.update_item(params)
end

# Function that stores the result returned by a process
def update_proc_result(task_name, proc_id, result)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS,
    update_expression: "SET procs.#PID.#RESULT = :r",
    expression_attribute_names: {
      "#PID" => "p#{proc_id.to_s}",
      "#RESULT" => 'result'
    },
    expression_attribute_values: {
      ':r' => result
    }
  }
  resp = dynamodb.update_item(params)
end

# Function that updates the state value of a process
def update_proc_state(task_name, proc_id, state)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_PROCS,
    update_expression: "SET procs.#PID.#STATE = :s",
    expression_attribute_names: {
      "#PID" => "p#{proc_id.to_s}",
      "#STATE" => 'state'
    },
    expression_attribute_values: {
      ':s' => state
    }
  }
  resp = dynamodb.update_item(params)

  if (state == 'FINISHED')
    params = {
      key: {
        taskName: task_name
      },
      table_name: DYNAMODB_TABLE_PROCS
    }
    resp = dynamodb.get_item(params)
    procs = resp.item['procs']
    key = 'p'+proc_id.to_s
    if (!procs[key]['condition'].nil?)
      ifprocess_id = procs[key]['condition']['ifProcess']
      ifprocess = procs[ifprocess_id]
      if (procs[key]['condition']['value'] == true)
        numThenProcessesFinished = ifprocess['numThenProcessesFinished'] + 1
        update_num_processes_finished(task_name, ifprocess_id, 'numThenProcessesFinished', numThenProcessesFinished)
        if (numThenProcessesFinished == ifprocess['numThenProcesses'])
          update_proc_state(task_name, ifprocess_id[1..ifprocess_id.length].to_i, 'FINISHED')
        end
      else
        numElseProcessesFinished = ifprocess['numElseProcessesFinished'] + 1
        update_num_processes_finished(task_name, ifprocess_id, 'numElseProcessesFinished', numElseProcessesFinished)
        if (numElseProcessesFinished == ifprocess['numElseProcesses'])
          update_proc_state(task_name, ifprocess_id[1..ifprocess_id.length].to_i, 'FINISHED')
        end
      end
    elsif (!procs[key]['forProcess'].nil?)
      forprocess_id = procs[key]['forProcess']
      forprocess = procs[forprocess_id]
      numProcessesFinished = forprocess['numProcessesFinished'] + 1
      update_num_processes_finished(task_name, forprocess_id, 'numProcessesFinished', numProcessesFinished)
      if (numProcessesFinished == forprocess['numProcesses'])
        numPendingIterations = forprocess['numPendingIterations'] - 1
        update_num_pending_iterations(task_name, forprocess_id, numPendingIterations)
        if (numPendingIterations == 0)
          update_proc_state(task_name, forprocess_id[1..forprocess_id.length].to_i, 'FINISHED')
        else
          revert_processes_state_to_initial_values(task_name, forprocess_id)
          update_num_processes_finished(task_name, forprocess_id, 'numProcessesFinished', 0)
        end
      end
    end
  end
end

# Function that updates the state value of a task
def update_task_state(task_name, state)
  dynamodb = Aws::DynamoDB::Client.new
  params = {
    key: {
      taskName: task_name
    },
    table_name: DYNAMODB_TABLE_TASKS,
    update_expression: "SET taskState = :s",
    expression_attribute_values: {
      ':s' => state
    }
  }
  resp = dynamodb.update_item(params)
end
