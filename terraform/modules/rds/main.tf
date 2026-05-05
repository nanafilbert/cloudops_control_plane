
terraform {
  required_providers {
    aws    = { 
     source = "hashicorp/aws"
     version = "~> 5.0" 
    }

    random = { 
      source = "hashicorp/random"
      version = "~> 3.0" 
    }
  }
}

# derive family dynamically — "16.3" → "postgres16"
resource "aws_db_parameter_group" "db_parameter_group" {
  name   = var.param_grp_name
  family = "postgres${split(".", var.engine_version)[0]}"

  tags = merge(var.tags, { Name = var.param_grp_name })
}


resource "aws_db_subnet_group" "db_subnet_group" {
  name       = var.subnet_grp_name
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = var.subnet_grp_name })
}



resource "random_password" "db" {
  length  = 16
  special = false
}

resource "aws_db_instance" "this" {
  identifier        = var.identifier
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  db_name           = var.db_name
  username          = var.db_username
  password          = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  parameter_group_name   = aws_db_parameter_group.db_parameter_group.name
  vpc_security_group_ids = [var.security_group_id]

  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = merge(var.tags, { Name = var.identifier })
}

resource "aws_secretsmanager_secret" "db" {
  name = var.secret_name
  tags = merge(var.tags, { Name = var.secret_name })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    db_name  = var.db_name
    username = var.db_username
    password = random_password.db.result
  })
}