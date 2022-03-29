# ---------------------------------------------------------------------------------------------------------------------
# THESE TEMPLATES REQUIRE TERRAFORM VERSION 0.12 AND ABOVE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 0.12"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN AUTO SCALING GROUP (ASG) TO RUN NOMAD
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_autoscaling_group" "autoscaling_group" {
  name_prefix = "${var.cluster_name}-"

  availability_zones  = var.availability_zones
  vpc_zone_identifier = var.subnet_ids

  min_size             = var.min_size
  max_size             = var.max_size
  desired_capacity     = var.desired_capacity
  termination_policies = var.termination_policies

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  wait_for_capacity_timeout = var.wait_for_capacity_timeout

  target_group_arns = var.target_group_arns

  launch_template {
    id      = aws_launch_template.launch_template.id
    version = "$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = flatten([
    {
      key                 = "Name"
      value               = var.cluster_name
      propagate_at_launch = true
    },
    var.tags,
  ])
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE LAUNCH TEMPLATE TO DEFINE WHAT RUNS ON EACH INSTANCE IN THE ASG
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_launch_template" "launch_template" {
  name_prefix   = "${var.cluster_name}-"
  image_id      = var.ami_id
  key_name      = var.ssh_key_name
  instance_type = var.instance_type
  user_data     = base64encode(var.user_data)

  update_default_version = true

  placement {
    group_name = var.enable_placement_group ? aws_placement_group.spread[0].id : null
    tenancy    = var.tenancy
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.instance_profile.name
  }

  # https://github.com/terraform-providers/terraform-provider-aws/issues/4570
  # See "Considerations" in:
  # https://docs.aws.amazon.com/autoscaling/ec2/userguide/create-launch-template.html
  network_interfaces {
    associate_public_ip_address = var.associate_public_ip_address
    security_groups             = concat([aws_security_group.lc_security_group.id], var.security_groups)
    delete_on_termination       = true
  }

  # root block device
  block_device_mappings {
    device_name = var.root_volume_device_name
    ebs {
      volume_type           = var.root_volume_type
      volume_size           = var.root_volume_size
      iops                  = var.root_volume_iops
      throughput            = contains(["gp3"], var.root_volume_type) ? var.root_volume_throughput : null
      delete_on_termination = var.root_volume_delete_on_termination
    }
  }

  metadata_options {
    # As of 2022-03-29, we must specify http_endpoint = "enabled", otherwise:
    #   Error: InvalidParameterValue: A value of ‘’ is not valid for http-endpoint. Valid values are ‘enabled’ or ‘disabled’.
    # https://github.com/hashicorp/terraform-provider-aws/issues/12564
    http_endpoint = "enabled"
    # https://aws.amazon.com/about-aws/whats-new/2022/01/instance-tags-amazon-ec2-instance-metadata-service/
    instance_metadata_tags = "enabled"
  }
}

resource "aws_placement_group" "spread" {
  count    = var.enable_placement_group ? 1 : 0
  name     = var.cluster_name
  strategy = "spread"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP TO CONTROL WHAT REQUESTS CAN GO IN AND OUT OF EACH EC2 INSTANCE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "lc_security_group" {
  name_prefix = "${var.cluster_name}-"
  description = "Security group for the ${var.cluster_name} launch configuration"
  vpc_id      = var.vpc_id

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    "Name" = var.cluster_name
  }
}

resource "aws_security_group_rule" "allow_ssh_inbound" {
  count       = length(var.allowed_ssh_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.ssh_port
  to_port     = var.ssh_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_ssh_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.lc_security_group.id
}

# ---------------------------------------------------------------------------------------------------------------------
# THE INBOUND/OUTBOUND RULES FOR THE SECURITY GROUP COME FROM THE NOMAD-SECURITY-GROUP-RULES MODULE
# ---------------------------------------------------------------------------------------------------------------------

module "security_group_rules" {
  source = "../nomad-security-group-rules"

  security_group_id           = aws_security_group.lc_security_group.id
  allowed_inbound_cidr_blocks = var.allowed_inbound_cidr_blocks

  http_port = var.http_port
  rpc_port  = var.rpc_port
  serf_port = var.serf_port
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH AN IAM ROLE TO EACH EC2 INSTANCE
# We can use the IAM role to grant the instance IAM permissions so we can use the AWS CLI without having to figure out
# how to get our secret AWS access keys onto the box.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = "${var.cluster_name}-"
  path        = var.instance_profile_path
  role        = aws_iam_role.instance_role.name

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "instance_role" {
  name_prefix        = "${var.cluster_name}-"
  assume_role_policy = data.aws_iam_policy_document.instance_role.json

  # aws_iam_instance_profile.instance_profile in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_region" "current" {}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    # Compatible with AWS China Regions
    # https://docs.amazonaws.cn/en_us/aws/latest/userguide/iam.html
    principals {
      type        = "Service"
      identifiers = [substr(data.aws_region.current.name, 0, 3) == "cn-" ? "ec2.amazonaws.com.cn" : "ec2.amazonaws.com"]
    }
  }
}

