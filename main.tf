terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-central-1"
}

resource "aws_security_group" "rds_sg" {
  name_prefix = "rds_sg_"
  description = "Allow MySQL access"
  vpc_id      = "vpc-06b2ed2efcaec4baf"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS security group"
  }
}


resource "aws_db_instance" "default" {
  allocated_storage    = 20
  db_name              = "finki_rasporedi_db"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "Ogan09875"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible =  true
}

resource "aws_ecs_cluster" "finki_rasporedi_ecs_cluster" {
  name = "finki-rasporedi-cluster"
}


resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com",
        },
      },
    ],
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}




resource "aws_ecs_task_definition" "finki_rasporedi_td_backend" {
  family                   = "finki_rasporedi_td_backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "finki_rasporedi_td_backend",
      image     = "nnikolovskii/aws-backend-healthy:latest",
      essential = true,
      portMappings = [
        {
          containerPort = 80
        }
      ]
    }
  ])
}


resource "aws_security_group" "ecs_service" {
  name        = "ecs_service_sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = "vpc-06b2ed2efcaec4baf"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_lb" "finki_rasporedi_lb" {
  name               = "finki-rasporedi-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_service.id]
  subnets            = ["subnet-098b735d5e502d566", "subnet-0cb88622e95956387", "subnet-002b6eeebcee42f91"]

  enable_deletion_protection = false
}


resource "aws_lb_target_group" "finki_rasporedi_lbt" {
  name     = "finki-rasporedi-lbt"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-06b2ed2efcaec4baf"
  target_type = "ip"

  health_check {
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}


resource "aws_lb_listener" "finki_rasporedi_lbl" {
  load_balancer_arn = aws_lb.finki_rasporedi_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.finki_rasporedi_lbt.arn
  }
}



resource "aws_ecs_service" "finki_rasporedi_service" {
  name            = "finki-rasporedi-service"
  cluster         = aws_ecs_cluster.finki_rasporedi_ecs_cluster.id
  task_definition = aws_ecs_task_definition.finki_rasporedi_td_backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-098b735d5e502d566", "subnet-0cb88622e95956387", "subnet-002b6eeebcee42f91"]
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.finki_rasporedi_lbt.arn
    container_name   = "finki_rasporedi_td_backend"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.finki_rasporedi_lbl]
}

data "aws_lb" "finki_rasporedi_lb" {
  name = aws_lb.finki_rasporedi_lb.name
}





resource "aws_s3_bucket" "finki_rasporedi_bucket" {
  bucket = "finki-rasporedi-bucket"

  tags = {
    Name = "FinkiRasporediBucket"
  }
}

resource "aws_s3_bucket_versioning" "finki_rasporedi_bucket_versioning" {
  bucket = aws_s3_bucket.finki_rasporedi_bucket.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "finki_rasporedi_bucket_encryption" {
  bucket = aws_s3_bucket.finki_rasporedi_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.finki_rasporedi_bucket.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "TerraformLockTable"
  }
}

//lool
data "aws_lb" "finki_rasporedi_lb_backend" {
  name = aws_lb.finki_rasporedi_lb.name
}

resource "aws_ecs_task_definition" "finki_rasporedi_td_frontend" {
  family                   = "finki_rasporedi_td_frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = "1024"
  memory                   = "3072"

  container_definitions = jsonencode([
    {
      name      = "finki_rasporedi_td_frontend",
      image     = "nnikolovskii/flutter-frontend:latest",
      essential = true,
      portMappings = [
        {
          containerPort = 8080
        }
      ]
      environment = [
        {
          name  = "API_URL"
          value = "http://${data.aws_lb.finki_rasporedi_lb_backend.dns_name}/api"
        }
      ]
    }
  ])

  depends_on = [
    aws_lb.finki_rasporedi_lb
  ]
}

resource "aws_security_group" "ecs_service_frontend" {
  name        = "ecs_service_sg_frontend"
  description = "Allow HTTP inbound traffic"
  vpc_id      = "vpc-06b2ed2efcaec4baf"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "finki_rasporedi_lbt_frontend" {
  name     = "finki-rasporedi-lbt-frontend"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = "vpc-06b2ed2efcaec4baf"
  target_type = "ip"

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb" "finki_rasporedi_lb_f" {
  name               = "finki-rasporedi-lb-f"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_service.id]
  subnets            = ["subnet-098b735d5e502d566", "subnet-0cb88622e95956387", "subnet-002b6eeebcee42f91"]

  enable_deletion_protection = false
}


resource "aws_lb_listener" "finki_rasporedi_lbl_frontend-f" {
  load_balancer_arn = aws_lb.finki_rasporedi_lb_f.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.finki_rasporedi_lbt_frontend.arn
  }
}

resource "aws_ecs_service" "finki_rasporedi_service_frontend" {
  name            = "finki-rasporedi-service-frontend"
  cluster         = aws_ecs_cluster.finki_rasporedi_ecs_cluster.id
  task_definition = aws_ecs_task_definition.finki_rasporedi_td_frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-098b735d5e502d566", "subnet-0cb88622e95956387", "subnet-002b6eeebcee42f91"]
    security_groups  = [aws_security_group.ecs_service_frontend.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.finki_rasporedi_lbt_frontend.arn
    container_name   = "finki_rasporedi_td_frontend"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.finki_rasporedi_lbl_frontend-f]
}

