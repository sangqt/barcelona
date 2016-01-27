require "rails_helper"

describe Barcelona::Network::NetworkStack do
  it "generates network stack CF template" do
    stack = described_class.new(
      "test-stack",
      cidr_block: '10.0.0.0/16',
      bastion_key_pair: 'bastion'
    )
    generated = JSON.load(stack.target!)
    expect(generated["Description"]).to eq "AWS CloudFormation for Barcelona network stack"
    expect(generated["AWSTemplateFormatVersion"]).to eq "2010-09-09"
    expected = {
      "VPC" => {
        "Type" => "AWS::EC2::VPC",
        "Properties" =>
        {
          "CidrBlock" => "10.0.0.0/16",
          "EnableDnsSupport" => true,
          "EnableDnsHostnames" => true,
          "Tags" =>
          [{"Key" => "Name", "Value" => {"Ref" => "AWS::StackName"}},
           {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}}]}},
      "InternetGateway" => {
        "Type" => "AWS::EC2::InternetGateway",
        "Properties" => {
          "Tags" =>
          [{"Key" => "Name", "Value" => {"Ref" => "AWS::StackName"}},
           {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
           {"Key" => "Network", "Value" => "Public"}]}},
      "VPCGatewayAttachment" => {
        "Type" => "AWS::EC2::VPCGatewayAttachment",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "InternetGatewayId" => {"Ref" => "InternetGateway"}}},
      "VPCDHCPOptions" => {
        "Type" => "AWS::EC2::DHCPOptions",
        "Properties" => {
          "DomainName" => {
            "Fn::Join" => [" ", ["ap-northeast-1.compute.internal", "bcn"]]},
          "DomainNameServers" => ["AmazonProvidedDNS"]}},
      "VPCDHCPOptionsAssociation" => {
        "Type" => "AWS::EC2::VPCDHCPOptionsAssociation",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "DhcpOptionsId" => {"Ref" => "VPCDHCPOptions"}}},
      "LocalHostedZone" => {
        "Type" => "AWS::Route53::HostedZone",
        "Properties" => {
          "Name" => "bcn",
          "VPCs" => [{"VPCId" => {"Ref" => "VPC"}, "VPCRegion" => {"Ref" => "AWS::Region"}}]}},
      "PublicELBSecurityGroup" => {
        "Type" => "AWS::EC2::SecurityGroup",
        "Properties" => {
          "GroupDescription" => "SG for Public ELB",
          "VpcId" => {"Ref" => "VPC"},
          "SecurityGroupIngress" => [
            {"IpProtocol" => "tcp",
             "FromPort" => 80,
             "ToPort" => 80,
             "CidrIp" => "0.0.0.0/0"},
            {"IpProtocol" => "tcp",
             "FromPort" => 443,
             "ToPort" => 443,
             "CidrIp" => "0.0.0.0/0"}]}},
      "PrivateELBSecurityGroup" => {
        "Type" => "AWS::EC2::SecurityGroup",
        "Properties" => {"GroupDescription" => "SG for Private ELB",
                         "VpcId" => {"Ref" => "VPC"},
                         "SecurityGroupIngress" => [
                           {"IpProtocol" => "tcp",
                            "FromPort" => 1,
                            "ToPort" => 65535,
                            "CidrIp" => "10.0.0.0/16"}]}},
      "ContainerInstanceAccessibleSecurityGroup" => {
        "Type" => "AWS::EC2::SecurityGroup",
        "Properties" => {
          "GroupDescription" => "accessible to container instances",
          "VpcId" => {"Ref" => "VPC"}}},
      "InstanceSecurityGroup" => {
        "Type" => "AWS::EC2::SecurityGroup",
        "Properties" => {
          "GroupDescription" => "SG for ECS container instances",
          "VpcId" => {"Ref" => "VPC"},
          "SecurityGroupIngress" => [
            {"IpProtocol" => "tcp",
             "FromPort" => 22,
             "ToPort" => 22,
             "SourceSecurityGroupId" => {"Ref" => "SecurityGroupBastion"}},
            {"IpProtocol" => "icmp",
             "FromPort" => -1,
             "ToPort" => -1,
             "CidrIp" => "10.0.0.0/16"},
            {"IpProtocol" => -1,
             "FromPort" => -1,
             "ToPort" => -1,
             "SourceSecurityGroupId" => {"Ref" => "PublicELBSecurityGroup"}},
            {"IpProtocol" => -1,
             "FromPort" => -1,
             "ToPort" => -1,
             "SourceSecurityGroupId" => {"Ref" => "PrivateELBSecurityGroup"}},
            {"IpProtocol" => -1,
             "FromPort" => -1,
             "ToPort" => -1,
             "SourceSecurityGroupId" =>
             {"Ref" => "ContainerInstanceAccessibleSecurityGroup"}}]}},
      "InstanceSecurityGroupSelfIngress" => {
        "Type" => "AWS::EC2::SecurityGroupIngress",
        "Properties" => {
          "GroupId" => {"Ref" => "InstanceSecurityGroup"},
          "IpProtocol" => -1,
          "FromPort" => -1,
          "ToPort" => -1,
          "SourceSecurityGroupId" => {"Ref" => "InstanceSecurityGroup"}}},
      "SecurityGroupBastion" => {
        "Type" => "AWS::EC2::SecurityGroup",
        "Properties" => {
          "GroupDescription" => "Security Group for bastion servers",
          "VpcId" => {"Ref" => "VPC"},
          "SecurityGroupIngress" => [
            {"IpProtocol" => "tcp",
             "FromPort" => 22,
             "ToPort" => 22,
             "CidrIp" => "0.0.0.0/0"},
            {"IpProtocol" => "udp",
             "FromPort" => 123,
             "ToPort" => 123,
             "CidrIp" => "10.0.0.0/16"}],
          "SecurityGroupEgress" => [
            {"IpProtocol" => -1,
             "FromPort" => -1,
             "ToPort" => -1,
             "CidrIp" => "0.0.0.0/0"}]}},
      "BastionServer" => {
        "Type" => "AWS::EC2::Instance",
        "DependsOn" => ["VPCGatewayAttachment"],
        "Properties" => {
          "InstanceType" => "t2.micro",
          "SourceDestCheck" => false,
          "ImageId" => "ami-383c1956",
          "KeyName" => "bastion",
          "NetworkInterfaces" => [
            {"AssociatePublicIpAddress" => true,
             "DeviceIndex" => 0,
             "SubnetId" => {"Ref" => "SubnetDmz1"},
             "GroupSet" => [{"Ref" => "SecurityGroupBastion"}]}],
          "Tags" => [
            {"Key" => "Name",
             "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "bastion"]]}}]}},
      "ECSInstanceProfile" => {
        "Type"=>"AWS::IAM::InstanceProfile",
        "Properties" => {
          "Path" => "/",
          "Roles" => [{"Ref"=>"ECSInstanceRole"}]
        }
      },
      "ECSInstanceRole" => {
        "Type"=>"AWS::IAM::Role",
        "Properties" => {
          "AssumeRolePolicyDocument" => {
            "Version"=>"2012-10-17",
            "Statement" => [
              {
                "Effect"=>"Allow",
                "Principal" => {"Service"=>["ec2.amazonaws.com"]},
                "Action"=>["sts:AssumeRole"]
              }
            ]
          },
          "Path"=>"/",
          "Policies" => [
            {
              "PolicyName" => "barcelona-ecs-container-instance-role",
              "PolicyDocument" => {
                "Version" => "2012-10-17",
                "Statement" => [
                  {
                    "Effect"=>"Allow",
                    "Action" => [
                      "ec2:AssociateAddress",
                      "ec2:TerminateInstances",
                      "ec2:DescribeInstances",
                      "ecs:CreateCluster",
                      "ecs:DeregisterContainerInstance",
                      "ecs:DiscoverPollEndpoint",
                      "ecs:Poll",
                      "ecs:RegisterContainerInstance",
                      "ecs:StartTelemetrySession",
                      "ecs:Submit*",
                      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
                      "elasticloadbalancing:DescribeLoadBalancers",
                      "s3:Get*",
                      "s3:List*"
                    ],
                    "Resource"=>["*"]
                  }
                ]
              }
            }
          ]
        }
      },
      "ECSServiceRole" => {
        "Type"=>"AWS::IAM::Role",
        "Properties" => {
          "AssumeRolePolicyDocument" => {
            "Version" => "2008-10-17",
            "Statement" => [
              {
                "Effect"=>"Allow",
                "Principal" => {
                  "Service" => ["ecs.amazonaws.com"]
                },
                "Action" => ["sts:AssumeRole"]
              }
            ]
          },
          "Path" => "/",
          "Policies" => [
            {
              "PolicyName" => "barcelona-ecs-container-instance-role",
              "PolicyDocument" => {
                "Version"=>"2012-10-17",
                "Statement" => [
                  {
                    "Effect"=>"Allow",
                    "Action"=>[
                      "elasticloadbalancing:Describe*",
                      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
                      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
                      "ec2:Describe*",
                      "ec2:AuthorizeSecurityGroupIngress"
                    ],
                    "Resource"=>["*"]
                  }
                ]
              }
            }
          ]
        }
      },
      "RouteTableDmz1" => {
        "Type" => "AWS::EC2::RouteTable",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "public"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Public"}]}},
      "RouteDmz1" => {
        "Type" => "AWS::EC2::Route",
        "DependsOn" => ["VPCGatewayAttachment"],
        "Properties" => {
          "RouteTableId" => {"Ref" => "RouteTableDmz1"},
          "DestinationCidrBlock" => "0.0.0.0/0",
          "GatewayId" => {"Ref" => "InternetGateway"}}},
      "NetworkAclDmz1" => {
        "Type" => "AWS::EC2::NetworkAcl",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "public"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Public"}]}},
      "InboundNetworkAclEntryDmz10" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz1"},
          "RuleNumber" => 100,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 22, "To" => 22},
          "Protocol" => 6}},
      "InboundNetworkAclEntryDmz11" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz1"},
          "RuleNumber" => 101,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 80, "To" => 80},
          "Protocol" => 6}},
      "InboundNetworkAclEntryDmz12" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz1"},
          "RuleNumber" => 102,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 443, "To" => 443},
          "Protocol" => 6}},
      "InboundNetworkAclEntryDmz13" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz1"},
          "RuleNumber" => 103,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 1024, "To" => 65535},
          "Protocol" => 6}},
      "InboundNetworkAclEntryDmz14" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz1"},
          "RuleNumber" => 104,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 1024, "To" => 65535},
          "Protocol" => 17}},
      "InboundNetworkAclEntryDmz15" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz1"},
          "RuleNumber" => 105,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 123, "To" => 123},
          "Protocol" => 17}},
      "InboundNetworkAclEntryDmz1ICMP" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz1"},
          "RuleNumber" => 200,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "Icmp" => {"Type" => -1, "Code" => -1},
          "Protocol" => 1}},
      "OutboundNetworkAclEntryDmz1" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz1"},
          "RuleNumber" => 100,
          "Protocol" => -1,
          "RuleAction" => "allow",
          "Egress" => true,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 0, "To" => 65535}}},
      "SubnetDmz1" => {
        "Type" => "AWS::EC2::Subnet",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "CidrBlock" => "10.0.129.0/24",
          "AvailabilityZone" =>
          {"Fn::Select" => [0, {"Fn::GetAZs" => {"Ref" => "AWS::Region"}}]},
          "Tags" => [
            {"Key" => "Name",
             "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "Dmz1"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Public"}]}},
      "SubnetRouteTableAssociationDmz1" => {
        "Type" => "AWS::EC2::SubnetRouteTableAssociation",
        "Properties" => {
          "SubnetId" => {"Ref" => "SubnetDmz1"},
          "RouteTableId" => {"Ref" => "RouteTableDmz1"}}},
      "SubnetNetworkAclAssociationDmz1" => {
        "Type" => "AWS::EC2::SubnetNetworkAclAssociation",
        "Properties" => {"SubnetId" => {"Ref" => "SubnetDmz1"},
                         "NetworkAclId" => {"Ref" => "NetworkAclDmz1"}}},
      "RouteTableDmz2" => {
        "Type" => "AWS::EC2::RouteTable",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "public"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Public"}]}},
      "RouteDmz2" => {
        "Type" => "AWS::EC2::Route",
        "DependsOn" => ["VPCGatewayAttachment"],
        "Properties" => {
          "RouteTableId" => {"Ref" => "RouteTableDmz2"},
          "DestinationCidrBlock" => "0.0.0.0/0",
          "GatewayId" => {"Ref" => "InternetGateway"}}},
      "NetworkAclDmz2" => {
        "Type" => "AWS::EC2::NetworkAcl",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "public"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Public"}]}},
      "InboundNetworkAclEntryDmz20" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"},
          "RuleNumber" => 100,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 22, "To" => 22},
          "Protocol" => 6}},
      "InboundNetworkAclEntryDmz21" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"},
          "RuleNumber" => 101,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 80, "To" => 80},
          "Protocol" => 6}},
      "InboundNetworkAclEntryDmz22" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"},
          "RuleNumber" => 102,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 443, "To" => 443},
          "Protocol" => 6}},
      "InboundNetworkAclEntryDmz23" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"},
          "RuleNumber" => 103,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 1024, "To" => 65535},
          "Protocol" => 6}},
      "InboundNetworkAclEntryDmz24" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"},
          "RuleNumber" => 104,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 1024, "To" => 65535},
          "Protocol" => 17}},
      "InboundNetworkAclEntryDmz25" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"},
          "RuleNumber" => 105,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 123, "To" => 123},
          "Protocol" => 17}},
      "InboundNetworkAclEntryDmz2ICMP" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"},
          "RuleNumber" => 200,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "Icmp" => {"Type" => -1, "Code" => -1},
          "Protocol" => 1}},
      "OutboundNetworkAclEntryDmz2" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"},
          "RuleNumber" => 100,
          "Protocol" => -1,
          "RuleAction" => "allow",
          "Egress" => true,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 0, "To" => 65535}}},
      "SubnetDmz2" => {
        "Type" => "AWS::EC2::Subnet",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "CidrBlock" => "10.0.130.0/24",
          "AvailabilityZone" => {"Fn::Select" => [1, {"Fn::GetAZs" => {"Ref" => "AWS::Region"}}]},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "Dmz2"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Public"}]}},
      "SubnetRouteTableAssociationDmz2" => {
        "Type" => "AWS::EC2::SubnetRouteTableAssociation",
        "Properties" => {
          "SubnetId" => {"Ref" => "SubnetDmz2"},
          "RouteTableId" => {"Ref" => "RouteTableDmz2"}}},
      "SubnetNetworkAclAssociationDmz2" => {
        "Type" => "AWS::EC2::SubnetNetworkAclAssociation",
        "Properties" => {
          "SubnetId" => {"Ref" => "SubnetDmz2"},
          "NetworkAclId" => {"Ref" => "NetworkAclDmz2"}}},
      "RouteTableTrusted1" => {
        "Type" => "AWS::EC2::RouteTable",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "private"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Private"}]}},
      "NetworkAclTrusted1" => {
        "Type" => "AWS::EC2::NetworkAcl",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "private"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Private"}]}},
      "InboundNetworkAclEntryTrusted10" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"},
          "RuleNumber" => 100,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "10.0.0.0/8",
          "PortRange" => {"From" => 22, "To" => 22},
          "Protocol" => 6}},
      "InboundNetworkAclEntryTrusted11" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"},
          "RuleNumber" => 101,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 80, "To" => 80},
          "Protocol" => 6}},
      "InboundNetworkAclEntryTrusted12" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"},
          "RuleNumber" => 102,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 443, "To" => 443},
          "Protocol" => 6}},
      "InboundNetworkAclEntryTrusted13" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"},
          "RuleNumber" => 103,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 1024, "To" => 65535},
          "Protocol" => 6}},
      "InboundNetworkAclEntryTrusted14" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"},
          "RuleNumber" => 104,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 1024, "To" => 65535},
          "Protocol" => 17}},
      "InboundNetworkAclEntryTrusted15" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"},
          "RuleNumber" => 105,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 123, "To" => 123},
          "Protocol" => 17}},
      "InboundNetworkAclEntryTrusted1ICMP" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"},
          "RuleNumber" => 200,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "Icmp" => {"Type" => -1, "Code" => -1},
          "Protocol" => 1}},
      "OutboundNetworkAclEntryTrusted1" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"},
          "RuleNumber" => 100,
          "Protocol" => -1,
          "RuleAction" => "allow",
          "Egress" => true,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 0, "To" => 65535}}},
      "SubnetTrusted1" => {
        "Type" => "AWS::EC2::Subnet",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "CidrBlock" => "10.0.1.0/24",
          "AvailabilityZone" => {"Fn::Select" => [0, {"Fn::GetAZs" => {"Ref" => "AWS::Region"}}]},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "Trusted1"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Private"}]}},
      "SubnetRouteTableAssociationTrusted1" => {
        "Type" => "AWS::EC2::SubnetRouteTableAssociation",
        "Properties" => {
          "SubnetId" => {"Ref" => "SubnetTrusted1"},
          "RouteTableId" => {"Ref" => "RouteTableTrusted1"}}},
      "SubnetNetworkAclAssociationTrusted1" => {
        "Type" => "AWS::EC2::SubnetNetworkAclAssociation",
        "Properties" => {
          "SubnetId" => {"Ref" => "SubnetTrusted1"},
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted1"}}},
      "RouteTableTrusted2" => {
        "Type" => "AWS::EC2::RouteTable",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "private"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Private"}]}},
      "NetworkAclTrusted2" => {
        "Type" => "AWS::EC2::NetworkAcl",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "private"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Private"}]}},
      "InboundNetworkAclEntryTrusted20" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"},
          "RuleNumber" => 100,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "10.0.0.0/8",
          "PortRange" => {"From" => 22, "To" => 22},
          "Protocol" => 6}},
      "InboundNetworkAclEntryTrusted21" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"},
          "RuleNumber" => 101,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 80, "To" => 80},
          "Protocol" => 6}},
      "InboundNetworkAclEntryTrusted22" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"},
          "RuleNumber" => 102,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 443, "To" => 443},
          "Protocol" => 6}},
      "InboundNetworkAclEntryTrusted23" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"},
          "RuleNumber" => 103,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 1024, "To" => 65535},
          "Protocol" => 6}},
      "InboundNetworkAclEntryTrusted24" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"},
          "RuleNumber" => 104,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 1024, "To" => 65535},
          "Protocol" => 17}},
      "InboundNetworkAclEntryTrusted25" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"},
          "RuleNumber" => 105,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 123, "To" => 123},
          "Protocol" => 17}},
      "InboundNetworkAclEntryTrusted2ICMP" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"},
          "RuleNumber" => 200,
          "RuleAction" => "allow",
          "Egress" => false,
          "CidrBlock" => "0.0.0.0/0",
          "Icmp" => {"Type" => -1, "Code" => -1},
          "Protocol" => 1}},
      "OutboundNetworkAclEntryTrusted2" => {
        "Type" => "AWS::EC2::NetworkAclEntry",
        "Properties" => {
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"},
          "RuleNumber" => 100,
          "Protocol" => -1,
          "RuleAction" => "allow",
          "Egress" => true,
          "CidrBlock" => "0.0.0.0/0",
          "PortRange" => {"From" => 0, "To" => 65535}}},
      "SubnetTrusted2" => {
        "Type" => "AWS::EC2::Subnet",
        "Properties" => {
          "VpcId" => {"Ref" => "VPC"},
          "CidrBlock" => "10.0.2.0/24",
          "AvailabilityZone" => {
            "Fn::Select" => [1, {"Fn::GetAZs" => {"Ref" => "AWS::Region"}}]},
          "Tags" => [
            {"Key" => "Name", "Value" => {"Fn::Join" => ["-", [{"Ref" => "AWS::StackName"}, "Trusted2"]]}},
            {"Key" => "Application", "Value" => {"Ref" => "AWS::StackName"}},
            {"Key" => "Network", "Value" => "Private"}]}},
      "SubnetRouteTableAssociationTrusted2" => {
        "Type" => "AWS::EC2::SubnetRouteTableAssociation",
        "Properties" => {
          "SubnetId" => {"Ref" => "SubnetTrusted2"},
          "RouteTableId" => {"Ref" => "RouteTableTrusted2"}}},
      "SubnetNetworkAclAssociationTrusted2" => {
        "Type" => "AWS::EC2::SubnetNetworkAclAssociation",
        "Properties" => {
          "SubnetId" => {"Ref" => "SubnetTrusted2"},
          "NetworkAclId" => {"Ref" => "NetworkAclTrusted2"}}}}
    expect(generated["Resources"]).to eq expected
  end

  context "when nat_type is instance" do
    it "includes NAT resources" do
      stack = described_class.new(
        "test-stack",
        cidr_block: '10.0.0.0/16',
        bastion_key_pair: 'bastion',
        nat_type: "instance"
      )
      generated = JSON.load(stack.target!)
      expect(generated["Resources"]["NAT1"]).to be_present
      expect(generated["Resources"]["SecurityGroupNAT"]).to be_present
      expect(generated["Resources"]["RouteNATForRouteTableTrusted1"]).to be_present
    end
  end
end
