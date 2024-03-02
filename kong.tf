data "aws_acm_certificate" "multisafe-test-cert" {
  domain      = "*.test.multisafe.finance"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

//===============================================RDS Module starts=========================================/
# RDS Security Group
resource "aws_security_group" "rds_sg" {
  name   = "${var.app_name}-RDS-SG"
  vpc_id = var.vpc_id

  ingress {
    description      = "Postgres access from ECS cluster"
    protocol         = "tcp"
    from_port        = 5432
    to_port          = 5432
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.local_internet_cidr]
  }

  tags = {
    Name = "${var.app_name}-RDS-SG"
    CreatedBy = var.CreatedBy
    environment = var.env
  }
}

module "db" {
  source = "terraform-aws-modules/rds/aws"
  identifier = var.identifier
  engine            = var.db_engine
  engine_version    = var.db_engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type = var.storage_type
  skip_final_snapshot = true
  db_name  = var.db_name
  username = var.db_username
  manage_master_user_password = true
  password = var.db_password
  port     = var.db_port
  iam_database_authentication_enabled = false

  backup_retention_period = var.backup_retention_period
  copy_tags_to_snapshot   = true

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period

  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    CreatedBy = var.CreatedBy
    env = var.env
    Purpose = var.Purpose
  }

  create_db_subnet_group = true
  subnet_ids             = var.subnet_ids

  family = var.family
  major_engine_version = var.major_engine_version

  create_db_parameter_group = true
  create_db_option_group    = false

  deletion_protection = false

  # Define custom parameters for your DB parameter group
    parameters = [
    {
      name  = "rds.force_ssl"
      value = "0"
    },
    {
      name  = "password_encryption"
      value = "md5"
    }
  ]
}

output "this_db_instance_endpoint" {
  value       = split(":", module.db.db_instance_endpoint)[0]
  description = "The connection endpoint for the RDS instance without the port number."
}

# output "this_db_instance_master_user_secret_arn" {
#   description = "The ARN of the master user secret (Only available when manage_master_user_password is set to true)"
#   value       = module.db.db_instance_master_user_secret_arn
# }

output "db_secret_arn" {
  value = module.db.db_instance_master_user_secret_arn
}

data "aws_secretsmanager_secret_version" "secrets" {
  # Fill in the name you gave to your secret
  secret_id = module.db.db_instance_master_user_secret_arn
}

//=====================================ECS module starts==========================================================//

module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws//modules/cluster"
  version   = "~> 5.9.1"

  cluster_name = var.ecs_cluster_name
  fargate_capacity_providers    = {
    FARGATE = {}
  }
  create_task_exec_iam_role = true
  tags = {
    CreatedBy = var.CreatedBy
    Environment = var.env
  }
}  

module "ecs_service_definition" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.9.1"

  name                         = var.ecs_service_name
  desired_count                = 1
  cluster_arn                  = module.ecs_cluster.arn
  enable_autoscaling           = false
  wait_for_steady_state        = true
  subnet_ids                   = var.subnet_ids
  security_group_rules  = {
    ingress_alb_service = {
      type                     = "ingress"
      from_port                = 0
      to_port                  = 0
      protocol                 = "-1"
      description              = "comminication between alb and ecs"
      cidr_blocks              = [var.vpc_cidr]
    }
    egress_all  = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [var.local_internet_cidr]
    }
  }
  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }
  load_balancer = [{
    container_name   = var.container_name
    container_port   = var.kong_proxy_port
    target_group_arn = module.alb.target_groups[var.kong_tg_proxy].arn
  },
  {
    container_name   = var.container_name
    container_port   = var.kong_admin_api_port
    target_group_arn = module.alb.target_groups[var.kong_tg_admin_api].arn
  },
  {
    container_name   = var.container_name
    container_port   = var.kong_admin_gui_port
    target_group_arn = module.alb.target_groups[var.kong_tg_admin_gui].arn
  }
  ]

  # Task Definition adjustments
  create_iam_role        = false
  task_exec_iam_role_arn = module.ecs_cluster.task_exec_iam_role_arn
  enable_execute_command = true

  container_definitions = {
  (var.container_name) = {
    name            = var.container_name
    image           = var.kong_image
    cpu             = var.kong_cpu
    memory          = var.kong_memory
    essential = true
    command   = ["/bin/sh", "-c", "kong migrations bootstrap && kong start"]
    readonly_root_filesystem = false
    port_mappings = [
      {
        containerPort : var.kong_proxy_port
        hostPort      : var.kong_proxy_port
        protocol      : "tcp"
        appProtocol   : "http"
      },
      {
        containerPort : var.kong_admin_api_port
        hostPort      : var.kong_admin_api_port
        protocol      : "tcp"
        appProtocol   : "http"
      },
      {
        containerPort : var.kong_admin_gui_port
        hostPort      : var.kong_admin_gui_port
        protocol      : "tcp"
        appProtocol   : "http"
      }
      ],
    environment = [
      { name = "KONG_ADMIN_GUI_API_URL", value = "${var.kong_base_url}:${var.kong_https_admin_api_port}" },
      { name = "KONG_REAL_IP_HEADER", value = "X-Forwarded-For" },
      { name = "KONG_PG_DATABASE", value = var.db_name },
      { name = "KONG_PG_PORT", value = var.db_port },
      { name = "KONG_PG_USER", value = var.db_username },
      { name = "KONG_PROXY_LISTEN", value = "0.0.0.0:8000" },
      { name = "KONG_ADMIN_GUI_LISTEN", value = "0.0.0.0:8002" },
      { name = "KONG_ADMIN_LISTEN", value = "0.0.0.0:8001" },
      { name = "KONG_DATABASE", value = var.db_engine },
      { name = "KONG_ADMIN_GUI_URL", value = "${var.kong_base_url}:${var.kong_https_admin_gui_port}" },
      { name = "KONG_TRUSTED_IPS", value = "0.0.0.0/0" },
      { name = "KONG_PG_HOST", value = split(":", module.db.db_instance_endpoint)[0] },
      # { name = "KONG_PG_PASSWORD", value = var.db_password }
    ],
    secrets = [
        {
            "name": "KONG_PG_PASSWORD",
            "valueFrom": "${module.db.db_instance_master_user_secret_arn}:password::"
        },
        ],
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/cs/v2/infra/kong-gw-task-def",
        "awslogs-region"        = "us-east-1",
        "awslogs-stream-prefix" = "ecs",
        "awslogs-create-group"  = "true",
      }
    }
  }
  }
  ignore_task_definition_changes = false
  depends_on = [module.alb]
  tags = {
    CreatedBy = var.CreatedBy
    Environment = var.env
  }
}
///////////============================================///////////////////////////////////////////

//ALB

module "alb" {
  source  = "terraform-aws-modules/alb/aws"

  name   = var.alb_name
  load_balancer_type = var.load_balancer_type
  internal = true
  vpc_id = var.vpc_id
  subnets = var.subnet_ids
  enable_deletion_protection    = false
  # Security Group
  security_group_ingress_rules = {
    https_access = {
      from_port   = var.alb_https_port
      to_port     = var.alb_https_port
      ip_protocol = "tcp"
      cidr_ipv4   = var.vpc_cidr
    },
    kong_https_admin_api_port = {
      from_port   = var.kong_https_admin_api_port
      to_port     = var.kong_https_admin_api_port
      ip_protocol = "tcp"
      cidr_ipv4   = var.vpc_cidr
    },
    kong_https_admin_gui_port = {
      from_port   = var.kong_https_admin_gui_port
      to_port     = var.kong_https_admin_gui_port
      ip_protocol = "tcp"
      cidr_ipv4   = var.vpc_cidr
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = var.local_internet_cidr
    }
  }

  listeners = {
    https_port = {
      port     = var.alb_https_port
      protocol = "HTTPS"
      certificate_arn = data.aws_acm_certificate.multisafe-test-cert.arn

      forward = {
        target_group_key = var.kong_tg_proxy
      }
    },
    kong_admin_api_port = {
      port     = var.kong_https_admin_api_port
      protocol = "HTTPS"
      certificate_arn = data.aws_acm_certificate.multisafe-test-cert.arn

      forward = {
        target_group_key = var.kong_tg_admin_api
      }
    },
    kong_gui_port = {
      port     = var.kong_https_admin_gui_port
      protocol = "HTTPS"
      certificate_arn = data.aws_acm_certificate.multisafe-test-cert.arn

      forward = {
        target_group_key = var.kong_tg_admin_gui
      }
    }
}

  target_groups = {
  (var.kong_tg_proxy) = {
    name = var.kong_tg_proxy
    backend_protocol = "HTTP"
    backend_port     = var.kong_proxy_port
    target_type      = "ip"
    health_check = {
      path    = "/"
      matcher = "200,404"
    }
    create_attachment = false
  },
  (var.kong_tg_admin_api) = {
    name = var.kong_tg_admin_api
    backend_protocol = "HTTP"
    backend_port     = var.kong_admin_api_port
    target_type      = "ip"
    health_check = {
      path    = "/"
      matcher = "200"
    }
    create_attachment = false
  },
  (var.kong_tg_admin_gui) = {
    name = var.kong_tg_admin_gui
    backend_protocol = "HTTP"
    backend_port     = var.kong_admin_gui_port
    target_type      = "ip"
    health_check = {
      path    = "/"
      matcher = "200"
    }
    create_attachment = false
  }
  }

  tags = {
    CreatedBy = var.CreatedBy
    Environment = var.env
  }
}

output "alb_target_group_arns" {
  description = "ARNs of the target groups created by the ALB module"
  value       = [module.alb.target_groups[var.kong_tg_proxy].arn, module.alb.target_groups[var.kong_tg_admin_api].arn, module.alb.target_groups[var.kong_tg_admin_gui].arn]
}
