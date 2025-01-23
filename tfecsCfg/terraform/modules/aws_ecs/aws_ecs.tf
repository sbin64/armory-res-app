# AWS ECS Terraform module
locals {
  final_ecs_service_name = var.ecs_service_name
  vpc_id                 = data.aws_subnet.selected.vpc_id
  environment_map = [
    for k, v in var.environment_variables :
    {
      name  = k
      value = v
    }
  ]
  internal_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  alb_port             = var.protocol == "HTTP" ? 80 : 443
}

data "aws_ecs_cluster" "this" {
  cluster_name = var.ecs_cluster_name
}

resource "aws_ecs_task_definition" "this" {
  task_role_arn            = var.task_role_arn
  family                   = local.final_ecs_service_name
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_container_cpu
  memory                   = var.ecs_task_container_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name        = var.ecs_task_container_name
    image       = var.ecs_task_image_url
    environment = local.environment_map
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    portMappings = [{
      containerPort = var.ecs_task_container_port
      hostPort      = var.ecs_task_container_port
    }]

  }])
  runtime_platform {
    cpu_architecture = var.cpu_architecture
  }


  tags = var.tags
}

resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/${local.final_ecs_service_name}"
  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name            = local.final_ecs_service_name
  cluster         = data.aws_ecs_cluster.this.arn
  task_definition = aws_ecs_task_definition.this.arn
  launch_type     = "FARGATE"
  desired_count   = var.ecs_service_desired_count
  network_configuration {
    subnets          = var.internal_alb ? var.private_subnet_ids : var.public_subnet_ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = !var.internal_alb
  }

  dynamic "load_balancer" {
    for_each = var.create_ingress_alb ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.ecs_task_container_name
      container_port   = var.ecs_task_container_port
    }
  }
  tags = var.tags
}

data "aws_iam_policy" "ecs_task_execution_role_policy" {
  name = "AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_execution_policy" {
  name   = "ecs_task_execution_policy"
  role   = aws_iam_role.ecs_task_execution_role.id
  policy = data.aws_iam_policy.ecs_task_execution_role_policy.policy
}

# Security group configuration for ECS
resource "aws_security_group" "ecs_service" {
  name        = "${local.final_ecs_service_name}-service-sg"
  description = "Security group for ${local.final_ecs_service_name} ECS service"
  vpc_id      = local.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_egress_rule" "ecs_service_egress" {
  security_group_id = aws_security_group.ecs_service.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "ecs_service_alb_ingress" {
  count                        = var.create_ingress_alb ? 1 : 0
  security_group_id            = aws_security_group.ecs_service.id
  from_port                    = var.ecs_task_container_port
  to_port                      = var.ecs_task_container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb[0].id
  tags                         = var.tags
}

# ALB configuration for ECS

resource "aws_security_group" "alb" {
  count       = var.create_ingress_alb ? 1 : 0
  name        = "${local.final_ecs_service_name}-alb-sg"
  description = "Security group for ${local.final_ecs_service_name} ECS service ALB"
  vpc_id      = local.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "alb_internal_access" {
  count             = var.create_ingress_alb && var.internal_alb ? length(local.internal_cidr_blocks) : 0
  security_group_id = aws_security_group.alb[0].id
  from_port         = var.ecs_task_container_port
  to_port           = var.ecs_task_container_port
  ip_protocol       = "tcp"
  cidr_ipv4         = local.internal_cidr_blocks[count.index]
  tags              = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "alb_public_access" {
  count             = var.create_ingress_alb && !var.internal_alb ? 1 : 0
  security_group_id = aws_security_group.alb[0].id
  from_port         = local.alb_port
  to_port           = local.alb_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = var.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_egress" {
  count             = var.create_ingress_alb ? 1 : 0
  security_group_id = aws_security_group.alb[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = var.tags
}

resource "aws_lb" "this" {
  count                      = var.create_ingress_alb ? 1 : 0
  name                       = local.final_ecs_service_name
  internal                   = var.internal_alb
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb[0].id]
  subnets                    = var.internal_alb ? var.private_subnet_ids : var.public_subnet_ids
  enable_deletion_protection = false
  tags                       = var.tags
}
resource "aws_lb_target_group" "this" {
  count       = var.create_ingress_alb ? 1 : 0
  name        = local.final_ecs_service_name
  port        = var.ecs_task_container_port
  protocol    = var.protocol
  vpc_id      = local.vpc_id
  target_type = "ip"
  tags        = var.tags
  health_check {
    enabled             = true
    interval            = 30
    path                = var.health_check_path
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "this" {
  count             = var.create_ingress_alb ? 1 : 0
  load_balancer_arn = aws_lb.this[0].arn
  port              = local.alb_port
  protocol          = var.protocol
  tags              = var.tags
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }
}

# terraform data sources
# Gets account ID
data "aws_caller_identity" "current" {}

# Used to get VPC ID
data "aws_subnet" "selected" {
  id = var.internal_alb ? var.private_subnet_ids[0] : var.public_subnet_ids[0]
}


## Outputs

output "ecs_service_name" {
  description = "The name of the ECS service"
  value       = local.final_ecs_service_name
}

output "ecs_service_arn" {
  description = "The ARN of the ECS service"
  value       = aws_ecs_service.this.id
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = var.create_ingress_alb ? aws_lb.this[0].dns_name : ""
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer"
  value       = var.create_ingress_alb ? aws_lb.this[0].arn : ""
}

output "ecs_service_security_group_id" {
  description = "The ID of the security group associated with the ECS service"
  value       = aws_security_group.ecs_service.id
}