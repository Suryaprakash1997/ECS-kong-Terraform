variable "app_name" {
  default = "kong"
}
variable "vpc_id" {
  default = "vpc-011f4c633f59f90bb"
}
variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}
variable "vpc_cidr" {
  default = "10.50.0.0/16"
}
variable "local_internet_cidr" {
  default = "0.0.0.0/0"
}

variable "aws_account_id" {
  description = "AWS account ID"
  default = "261623910215"
}
# DB
variable "identifier" {
  default = "cs-infra-v2-kong-rds-db"
}
variable "db_engine" {
  default = "postgres"
}
variable "db_engine_version" {
  default = 15.6
}
variable "db_port" {
  default = 5432
}
variable "max_allocated_storage" {
  default = 1000
}
variable "instance_class" {
  default = "db.t4g.medium"
}
variable "allocated_storage" {
  default = "20"
}
variable "storage_type" {
  default = "gp3"
}
variable "backup_retention_period" {
  default = 7
}
variable "performance_insights_retention_period" {
  default = 7
}
variable "db_name" {
  default = "kong"
}
variable "db_username" {
  default = "kong"
}
variable "CreatedBy" {
  default = "Surya"
}
variable "Purpose" {
  default = "DB for infra"
}
variable "env" {
  default = "infra"
}
variable "subnet_ids" {
  description = "A list of subnet IDs"
  type        = list(string)
  default     = ["subnet-0e0d3d84cee0a504f", "subnet-03c825b5ea033aa1b", "subnet-0ddd0e9cf4751330a"]
}
variable "family" {
  default = "postgres15"
}
variable "major_engine_version" {
  default = 15
}


#ALB
variable "alb_name" {
  default = "cs-infra-v2-kong-alb"
}
variable "load_balancer_type" {
  default = "application"
}
variable "alb_https_port" {
  default = 443
}
variable "kong_https_admin_gui_port" {
  default = 8445
}
variable "kong_https_admin_api_port" {
  default = 8444
}
variable "kong_tg_proxy" {
  default = "kong-proxy-tg"
}
variable "kong_tg_admin_api" {
  default = "kong-admin-tg"
}
variable "kong_tg_admin_gui" {
  default = "kong-admin-gui-tg"
}

#Task-definition
variable "container_name" {
  default = "kong"
}
variable "awslogs_group" {
  default = "/ecs/cs/v2/infra/kong-gw-task-def"
}
variable "awslogs_region" {
  default = "us-east-1"
}
variable "awslogs_stream_prefix" {
  default = "ecs"
}
variable "kong_image" {
  default = "261623910215.dkr.ecr.us-east-1.amazonaws.com/kong-image:latest"
}
variable "kong_cpu" {
  default = 1024
}
variable "kong_memory" {
  default = 2048
}

#ECS
variable "ecs_cluster_name" {
  default = "cs-infra-v2-kong-cluster"
}
variable "ecs_service_name" {
  default = "cs-infra-v2-kong-ecs-service"
}
variable "ecs_service_desired_count" {
  default = 1
}
variable "kong_proxy_port" {
  default = 8000
}
variable "kong_admin_api_port" {
  default = 8001
}
variable "kong_admin_gui_port" {
  default = 8002
}
variable "kong_base_url" {
  default = "https://v3-bridge.test.multisafe.finance"  
}
