module Barcelona
  module Network
    class AutoscalingBuilder < CloudFormation::Builder
      # http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
      # amzn-ami-2016.09.c-amazon-ecs-optimized
      ECS_OPTIMIZED_AMI_IDS = {
        "us-east-1" => "ami-6df8fe7a",
        "us-east-2" => "ami-c6b5efa3",
        "us-west-1" => "ami-1eda8d7e",
        "us-west-2" => "ami-a2ca61c2",
        "eu-west-1" => "ami-ba346ec9",
        "eu-central-1" => "ami-e012d48f",
        "ap-northeast-1" => "ami-08f7956f",
        "ap-southeast-1" => "ami-f4832f97",
        "ap-southeast-2" => "ami-774b7314",
        "ca-central-1" => "ami-be45f7da"
      }

      def ebs_optimized_by_default?
        !!(instance_type =~ /\A(c4|m4|d2)\..*\z/)
      end

      def build_resources
        add_resource("AWS::AutoScaling::LaunchConfiguration",
                     "ContainerInstanceLaunchConfiguration") do |j|

          j.IamInstanceProfile ref("ECSInstanceProfile")
          j.ImageId ECS_OPTIMIZED_AMI_IDS[stack.district.region]
          j.InstanceType instance_type
          j.SecurityGroups [ref("InstanceSecurityGroup")]
          j.UserData instance_user_data
          j.EbsOptimized ebs_optimized_by_default?
          j.BlockDeviceMappings [
            # Root volume
            {
              "DeviceName" => "/dev/xvda",
              "Ebs" => {
                "DeleteOnTermination" => true,
                "VolumeSize" => 20,
                "VolumeType" => "gp2"
              }
            },
            # devicemapper volume used by docker
            {
              "DeviceName" => "/dev/xvdcz",
              "Ebs" => {
                "DeleteOnTermination" => true,
                "VolumeSize" => 80,
                "VolumeType" => "gp2"
              }
            }
          ]
        end

        add_resource(AutoScalingGroup,
                     "ContainerInstanceAutoScalingGroup",
                     desired_capacity: desired_capacity)
      end

      def instance_user_data
        user_data = options[:container_instance].user_data
        user_data.run_commands += [
          "start ecs",
          "sleep 10", # Wait for ecs agent to be running
          "ecs_cluster=$(curl http://localhost:51678/v1/metadata | jq -r .Cluster)",
          # Wait for all tasks in the cluster to be running
          "while : ; do",
          "  pending_tasks_count=$(aws ecs describe-clusters --region=$AWS_REGION --clusters=$ecs_cluster | jq -r .clusters[0].pendingTasksCount)",
          "  [[ $pending_tasks_count -eq 0 ]] && break",
          "  sleep 3",
          "done",
          "sleep 30", # Wait for services to be attached to ELB
          "/opt/aws/bin/cfn-signal -e $? --region $AWS_REGION --stack #{stack.name} --resource ContainerInstanceAutoScalingGroup || true"
        ]
        user_data.build
      end

      def instance_type
        options[:instance_type]
      end

      def desired_capacity
        options[:desired_capacity]
      end
    end
  end
end
