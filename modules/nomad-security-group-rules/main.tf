# ---------------------------------------------------------------------------------------------------------------------
# THESE TEMPLATES REQUIRE TERRAFORM VERSION 0.12 AND ABOVE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 0.12"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE SECURITY GROUP RULES THAT CONTROL WHAT TRAFFIC CAN GO IN AND OUT OF A NOMAD CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group_rule" "allow_http_inbound" {
  type        = "ingress"
  from_port   = var.http_port
  to_port     = var.http_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "allow_rpc_inbound" {
  type        = "ingress"
  from_port   = var.rpc_port
  to_port     = var.rpc_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "allow_serf_tcp_inbound" {
  type        = "ingress"
  from_port   = var.serf_port
  to_port     = var.serf_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "allow_serf_udp_inbound" {
  type        = "ingress"
  from_port   = var.serf_port
  to_port     = var.serf_port
  protocol    = "udp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = var.security_group_id
}

# Similar to the allow_*_inbound rules, allow inbound from self

resource "aws_security_group_rule" "allow_http_inbound_from_self" {
  type      = "ingress"
  from_port = var.http_port
  to_port   = var.http_port
  protocol  = "tcp"
  self      = true

  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "allow_rpc_inbound_from_self" {
  type      = "ingress"
  from_port = var.rpc_port
  to_port   = var.rpc_port
  protocol  = "tcp"
  self      = true

  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "allow_serf_tcp_inbound_from_self" {
  type      = "ingress"
  from_port = var.serf_port
  to_port   = var.serf_port
  protocol  = "tcp"
  self      = true

  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "allow_serf_udp_inbound_from_self" {
  type      = "ingress"
  from_port = var.serf_port
  to_port   = var.serf_port
  protocol  = "udp"
  self      = true

  security_group_id = var.security_group_id
}
