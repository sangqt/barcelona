module CloudFormation
  class Executor
    attr_accessor :stack, :client

    def initialize(stack, client)
      @stack = stack
      @client = client
    end

    def describe
      client.describe_stacks(stack_name: stack.name).stacks[0]
    rescue Aws::CloudFormation::Errors::ValidationError
      # when a stack doesn't exist
      nil
    end

    # Returns nil if a stack is not created
    def stack_status
      describe&.stack_status
    end

    def create
      client.create_stack(stack_options)
    end

    def update
      client.update_stack(stack_options)
    rescue Aws::CloudFormation::Errors::ValidationError => e
      if e.message == "No updates are to be performed."
        Rails.logger.warn "No updates are to be performed."
      else
        raise e
      end
    end

    def stack_options
      {
        stack_name: stack.name,
        capabilities: ["CAPABILITY_IAM"],
        template_body: stack.target!
      }
    end

    def create_or_update
      case stack_status
      when nil, "DELETE_COMPLETE" then
        create
      when "CREATE_COMPLETE", "UPDATE_COMPLETE", "ROLLBACK_COMPLETE", "UPDATE_ROLLBACK_COMPLETE"
        update
      else
        raise "Applying stack template in progress"
      end
    end

    # Returns CF ID => Real ID hash
    def resource_ids
      return @resource_ids if @resource_ids
      resp = client.describe_stack_resources(stack_name: stack.name).stack_resources
      @resource_ids = Hash[*resp.map { |r| [r.logical_resource_id, r.physical_resource_id] }.flatten]
    end

    def outputs
      Hash[*describe.outputs.map{ |o| [o.output_key, o.output_value] }.flatten]
    end

    def delete
      client.delete_stack(stack_name: stack.name) if stack_status
    end
  end
end