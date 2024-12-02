#
# hhc-arch/aws/dispatcher/lambda_function.rb
#
require 'dispatcher.inc'

def lambda_handler(event:, context:)
  # Poll the messages retrieved in every single batch of the Lambda function and orchestrate everything
  event['Records'].each do |msg|
    message = JSON.parse(msg['body'])
    message_type = message['type']
    case message_type
      when 'process-register'
        resend_process_register_message(msg['body'])

      when 'process-response'
        response = message['response']
        update_proc_result(response['taskName'], response['procId'], response['result'])
        update_proc_state(response['taskName'], response['procId'], 'FINISHED')
        # Run the processes with their dependencies resolved
        procs_to_be_run = get_procs_to_be_run(response['taskName'])
        procs_to_be_run.each do |p|
          process_queue_name = p['procName'] + '-queue-' + p['procCloudProvider']
          send_process_trigger_message(p['taskName'], p['procId'], p['procParams'], process_queue_name)
          update_proc_state(p['taskName'], p['procId'], 'RUNNING')
        end
        # Check if the current task has completed
        if (procs_to_be_run.empty?)
          if (task_completed(response['taskName']))
            update_task_state(response['taskName'], 'FINISHED')
            task = get_task_data(response['taskName'])
            task_result = []
            task['outProcs'].each do |pid|
              pid = pid.to_i
              proc_result = get_proc_result(task['taskName'], pid)
              result = {
                'procId' => pid,
                'result' => proc_result
              }
              task_result << result
            end
            send_notification(task['taskName'], task['taskState'], task['notificationEmail'])
          end
        end

      when 'task'
        task = message['task']
        ack_code, ack_msg = initialize_task(task)
        if (ack_code == 0)
          send_notification(task['name'], 'RUNNING', task['notificationEmail'])
          # Run the processes with no dependencies
          procs_to_be_run = get_procs_to_be_run(task['name'])
          procs_to_be_run.each do |p|
            process_queue_name = p['procName'] + '-queue-' + p['procCloudProvider']
            send_process_trigger_message(p['taskName'], p['procId'], p['procParams'], process_queue_name)
            update_proc_state(p['taskName'], p['procId'], 'RUNNING')
          end
        end
    end
  end

  { statusCode: 200, body: JSON.generate('AWS Lambda Function: dispatcher') }
end
