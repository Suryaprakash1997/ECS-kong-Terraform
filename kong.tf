terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  //DB
  app_name                              = "kong"
  vpc_id                                = "vpc-011f4c633f59f90bb"
  aws_region                            = "us-east-1"
  vpc_cidr                              = "10.50.0.0/16"
  local_internet_cidr                   = "0.0.0.0/0"
  aws_account_id                        = "261623910215"
  identifier                            = "cs-infra-v2-kong-rds-db"
  db_engine                             = "postgres"
  db_engine_version                     = 15.6
  db_port                               = 5432
  max_allocated_storage                 = 1000
  instance_class                        = "db.t4g.medium"
  allocated_storage                     = 20
  storage_type                          = "gp3"
  backup_retention_period               = 7
  performance_insights_retention_period = 7
  db_name                               = "kong"
  db_username                           = "kong"
  subnet_ids                            = ["subnet-0e0d3d84cee0a504f", "subnet-03c825b5ea033aa1b", "subnet-0ddd0e9cf4751330a"]
  family                                = "postgres15"
  major_engine_version                  = 15
  //ALB
  alb_name                              = "cs-infra-v2-kong-alb"
  load_balancer_type                    = "application"
  alb_https_port                        = 443
  kong_https_admin_api_port             = 8444
  kong_https_admin_gui_port             = 8445
  kong_tg_proxy                         = "kong-proxy-tg"
  kong_tg_admin_api                     = "kong-admin-tg"
  kong_tg_admin_gui                     = "kong-admin-gui-tg"
  //TASK-DEFINITION
  container_name                        = "kong"
  awslogs_group                         = "/ecs/cs/v2/infra/kong-gw-task-def"
  awslogs_region                        = "us-east-1"
  awslogs_stream_prefix                 = "ecs"
  kong_image                            = "261623910215.dkr.ecr.us-east-1.amazonaws.com/kong-image:latest"
  kong_cpu                              = 1024
  kong_memory                           = 2048
  //ECS
  ecs_cluster_name                      = "cs-infra-v2-kong-cluster"
  ecs_service_name                      = "cs-infra-v2-kong-ecs-service"
  ecs_service_desired_count             = 1
  kong_proxy_port                       = 8000
  kong_admin_api_port                   = 8001
  kong_admin_gui_port                   = 8002
  kong_base_url                         = "https://v3-bridge.test.multisafe.finance"
  //TAGS
  CreatedBy                             = "surya"
  Purpose                               = "DB for Infra"
  env                                   = "infra"
}

data "aws_acm_certificate" "multisafe-test-cert" {
  domain      = "*.test.multisafe.finance"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

//===============================================RDS Module starts=========================================/
# RDS Security Group
resource "aws_security_group" "rds_sg" {
  name   = "cs-infra-${local.app_name}-RDS-SG"
  vpc_id = local.vpc_id

  ingress {
    description      = "Postgres access from ECS cluster"
    protocol         = "tcp"
    from_port        = local.db_port
    to_port          = local.db_port
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.local_internet_cidr]
  }

  tags = {
    Name = "${local.app_name}-RDS-SG"
    CreatedBy = local.CreatedBy
    environment = local.env
  }
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier = local.identifier
  engine            = local.db_engine
  engine_version    = local.db_engine_version
  instance_class    = local.instance_class
  allocated_storage = local.allocated_storage
  max_allocated_storage = local.max_allocated_storage
  storage_type = local.storage_type
  skip_final_snapshot = true
  db_name  = local.db_name
  username = local.db_username
  manage_master_user_password = true
  port     = local.db_port
  iam_database_authentication_enabled = false

  backup_retention_period = local.backup_retention_period
  copy_tags_to_snapshot   = true

  performance_insights_enabled          = true
  performance_insights_retention_period = local.performance_insights_retention_period

  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    CreatedBy = local.CreatedBy
    env = local.env
    Purpose = local.Purpose
  }

  create_db_subnet_group = true
  subnet_ids             = local.subnet_ids

  family = local.family
  major_engine_version = local.major_engine_version

  create_db_parameter_group = true
  create_db_option_group    = false

  deletion_protection = false

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

output "db_secret_arn" {
  value = module.db.db_instance_master_user_secret_arn
}

data "aws_secretsmanager_secret_version" "secrets" {
  secret_id = module.db.db_instance_master_user_secret_arn
}

//=====================================ECS module starts==========================================================//

module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws//modules/cluster"
  version   = "~> 5.9.1"

  cluster_name = local.ecs_cluster_name
  fargate_capacity_providers    = {
    FARGATE = {}
  }
  create_task_exec_iam_role = true
  tags = {
    CreatedBy = local.CreatedBy
    Environment = local.env
  }
}  

module "ecs_service_definition" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.9.1"

  name                         = local.ecs_service_name
  desired_count                = 1
  cluster_arn                  = module.ecs_cluster.arn
  enable_autoscaling           = false
  wait_for_steady_state        = true
  subnet_ids                   = local.subnet_ids
  security_group_rules  = {
    ingress_alb_service = {
      type                     = "ingress"
      from_port                = 0
      to_port                  = 0
      protocol                 = "-1"
      description              = "comminication between alb and ecs"
      cidr_blocks              = [local.vpc_cidr]
    }
    egress_all  = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [local.local_internet_cidr]
    }
  }
  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }
  load_balancer = [{
    container_name   = local.container_name
    container_port   = local.kong_proxy_port
    target_group_arn = module.alb.target_groups[local.kong_tg_proxy].arn
  },
  {
    container_name   = local.container_name
    container_port   = local.kong_admin_api_port
    target_group_arn = module.alb.target_groups[local.kong_tg_admin_api].arn
  },
  {
    container_name   = local.container_name
    container_port   = local.kong_admin_gui_port
    target_group_arn = module.alb.target_groups[local.kong_tg_admin_gui].arn
  }
  ]

  create_iam_role        = false
  task_exec_iam_role_arn = module.ecs_cluster.task_exec_iam_role_arn
  enable_execute_command = true

  container_definitions = {
  (local.container_name) = {
    name            = local.container_name
    image           = local.kong_image
    cpu             = local.kong_cpu
    memory          = local.kong_memory
    essential = true
    command   = ["/bin/sh", "-c", "kong migrations bootstrap && kong start"]
    readonly_root_filesystem = false
    port_mappings = [
      {
        containerPort : local.kong_proxy_port
        hostPort      : local.kong_proxy_port
        protocol      : "tcp"
        appProtocol   : "http"
      },
      {
        containerPort : local.kong_admin_api_port
        hostPort      : local.kong_admin_api_port
        protocol      : "tcp"
        appProtocol   : "http"
      },
      {
        containerPort : local.kong_admin_gui_port
        hostPort      : local.kong_admin_gui_port
        protocol      : "tcp"
        appProtocol   : "http"
      }
      ],
    environment = [
      { name = "KONG_ADMIN_GUI_API_URL", value = "${local.kong_base_url}:${local.kong_https_admin_api_port}" },
      { name = "KONG_REAL_IP_HEADER", value = "X-Forwarded-For" },
      { name = "KONG_PG_DATABASE", value = local.db_name },
      { name = "KONG_PG_PORT", value = local.db_port },
      { name = "KONG_PG_USER", value = local.db_username },
      { name = "KONG_PROXY_LISTEN", value = "0.0.0.0:8000" },
      { name = "KONG_ADMIN_GUI_LISTEN", value = "0.0.0.0:8002" },
      { name = "KONG_ADMIN_LISTEN", value = "0.0.0.0:8001" },
      { name = "KONG_DATABASE", value = local.db_engine },
      { name = "KONG_ADMIN_GUI_URL", value = "${local.kong_base_url}:${local.kong_https_admin_gui_port}" },
      { name = "KONG_TRUSTED_IPS", value = "0.0.0.0/0" },
      { name = "KONG_PG_HOST", value = split(":", module.db.db_instance_endpoint)[0] },
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
        "awslogs-group"         = local.awslogs_group,
        "awslogs-region"        = local.awslogs_region,
        "awslogs-stream-prefix" = local.awslogs_stream_prefix,
        "awslogs-create-group"  = "true",
      }
    }
  }
  }
  ignore_task_definition_changes = false
  depends_on = [module.alb]
  tags = {
    CreatedBy = local.CreatedBy
    Environment = local.env
  }
}
//=====================ALB MODULE STARTS=========================================//

//ALB
module "alb" {
  source  = "terraform-aws-modules/alb/aws"

  name   = local.alb_name
  load_balancer_type = local.load_balancer_type
  internal = true
  vpc_id = local.vpc_id
  subnets = local.subnet_ids
  enable_deletion_protection    = false
  # Security Group
  security_group_ingress_rules = {
    https_access = {
      from_port   = local.alb_https_port
      to_port     = local.alb_https_port
      ip_protocol = "tcp"
      cidr_ipv4   = local.vpc_cidr
    },
    kong_https_admin_api_port = {
      from_port   = local.kong_https_admin_api_port
      to_port     = local.kong_https_admin_api_port
      ip_protocol = "tcp"
      cidr_ipv4   = local.vpc_cidr
    },
    kong_https_admin_gui_port = {
      from_port   = local.kong_https_admin_gui_port
      to_port     = local.kong_https_admin_gui_port
      ip_protocol = "tcp"
      cidr_ipv4   = local.vpc_cidr
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = local.local_internet_cidr
    }
  }

  listeners = {
    https_port = {
      port     = local.alb_https_port
      protocol = "HTTPS"
      certificate_arn = data.aws_acm_certificate.multisafe-test-cert.arn

      forward = {
        target_group_key = local.kong_tg_proxy
      }
    },
    kong_admin_api_port = {
      port     = local.kong_https_admin_api_port
      protocol = "HTTPS"
      certificate_arn = data.aws_acm_certificate.multisafe-test-cert.arn

      forward = {
        target_group_key = local.kong_tg_admin_api
      }
    },
    kong_gui_port = {
      port     = local.kong_https_admin_gui_port
      protocol = "HTTPS"
      certificate_arn = data.aws_acm_certificate.multisafe-test-cert.arn

      forward = {
        target_group_key = local.kong_tg_admin_gui
      }
    }
}

  target_groups = {
  (local.kong_tg_proxy) = {
    name = local.kong_tg_proxy
    backend_protocol = "HTTP"
    backend_port     = local.kong_proxy_port
    target_type      = "ip"
    health_check = {
      path    = "/"
      matcher = "200,404"
    }
    create_attachment = false
  },
  (local.kong_tg_admin_api) = {
    name = local.kong_tg_admin_api
    backend_protocol = "HTTP"
    backend_port     = local.kong_admin_api_port
    target_type      = "ip"
    health_check = {
      path    = "/"
      matcher = "200"
    }
    create_attachment = false
  },
  (local.kong_tg_admin_gui) = {
    name = local.kong_tg_admin_gui
    backend_protocol = "HTTP"
    backend_port     = local.kong_admin_gui_port
    target_type      = "ip"
    health_check = {
      path    = "/"
      matcher = "200"
    }
    create_attachment = false
  }
  }

  tags = {
    CreatedBy = local.CreatedBy
    Environment = local.env
  }
}

output "alb_target_group_arns" {
  description = "ARNs of the target groups created by the ALB module"
  value       = [module.alb.target_groups[local.kong_tg_proxy].arn, module.alb.target_groups[local.kong_tg_admin_api].arn, module.alb.target_groups[local.kong_tg_admin_gui].arn]
}
