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

resource "aws_security_group" "ec2_security_group" {
  name        = "terraform-ec2-sg"
  description = "Security group for ec2 instance"
  vpc_id      = "vpc-06b2ed2efcaec4baf"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

resource "aws_instance" "example" {
  ami           = "ami-0910ce22fbfa68e1d"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.ec2_security_group.name]

  user_data =  <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y docker
              sudo service docker start
              sudo usermod -a -G docker ec2-user
              sudo docker pull nnikolovskii/aws-backend:latest
              sudo docker run -d --name aws-backend -p 80:80 nnikolovskii/aws-backend:latest
              EOF

  tags = {
    Name = "terraform-example1"
  }
}

resource "aws_launch_template" "my_launch_template" {
  name_prefix   = "backend-"
  image_id      = "ami-0910ce22fbfa68e1d"
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }

  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y docker
              sudo service docker start
              sudo usermod -a -G docker ec2-user
              sudo docker pull nnikolovskii/aws-backend:latest
              sudo docker run -d --name aws-backend -p 80:80 nnikolovskii/aws-backend:latest
              EOF
  )
}

resource "aws_lb_target_group" "my_target_group" {
  name     = "my-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-06b2ed2efcaec4baf"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

resource "aws_security_group" "lb_security_group" {
  name        = "lb_security_group"
  description = "Security group for load balancer"
  vpc_id      = "vpc-06b2ed2efcaec4baf"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # All traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lb_security_group"
  }
}


resource "aws_lb" "my-lb" {
  name               = "my-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_security_group.id]
  subnets            = ["subnet-098b735d5e502d566", "subnet-0cb88622e95956387", "subnet-002b6eeebcee42f91"]

  enable_deletion_protection = false

  idle_timeout = 60
}

resource "aws_lb_listener" "my-lb-listener" {
  load_balancer_arn = aws_lb.my-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

resource "aws_autoscaling_group" "my-ag" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = ["subnet-098b735d5e502d566", "subnet-0cb88622e95956387", "subnet-002b6eeebcee42f91"]
  launch_template {
    id      = aws_launch_template.my_launch_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.my_target_group.arn]

  tag {
    key                 = "Name"
    value               = "example-asg-instance"
    propagate_at_launch = true
  }
}


output "load_balancer_dns_name" {
  value = aws_lb.my-lb.dns_name
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.my-ag.name
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
