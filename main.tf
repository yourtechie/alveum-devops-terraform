provider "aws" {
  region = var.aws_region
}

# 1. Create a VPC with public and private subnets
resource "aws_vpc" "alveum_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "AlveumVpc"
  }
}

resource "aws_subnet" "public_subnet" {
  count = 2
  vpc_id = aws_vpc.alveum_vpc.id
  cidr_block = cidrsubnet(aws_vpc.alveum_vpc.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count = 2
  vpc_id = aws_vpc.alveum_vpc.id
  cidr_block = cidrsubnet(aws_vpc.alveum_vpc.cidr_block, 8, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "PrivateSubnet-${count.index}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.alveum_vpc.id
  tags = {
    Name = "AlveumIGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.alveum_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count = 2
  subnet_id = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# 2. Create an RDS PostgreSQL instance with RDS Proxy
resource "aws_db_instance" "alveum_db" {
  identifier = "alveumdb"
  engine = "postgres"
  engine_version = "13.7"
  instance_class = "db.t3.micro"
  allocated_storage = 20
  username = var.db_username
  password = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.alveum_db_subnet_group.name
  skip_final_snapshot = true
  publicly_accessible = false
}

resource "aws_db_subnet_group" "alveum_db_subnet_group" {
  name = "alveum-db-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id
  tags = {
    Name = "AlveumDBSubnetGroup"
  }
}

resource "aws_db_proxy" "alveum_db_proxy" {
  name = "alveum-db-proxy"
  engine_family = "POSTGRESQL"
  role_arn = aws_iam_role.rds_proxy_role.arn
  vpc_subnet_ids = aws_subnet.private_subnet[*].id
  auth {
    auth_scheme = "SECRETS"
    description = "RDS Proxy Auth"
    iam_auth = "DISABLED"
    secret_arn = aws_secretsmanager_secret.db_credentials.arn
  }
}

# 3. Create an ElasticCache Redis cluster
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name = "alveum-redis-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id
}

resource "aws_elasticache_cluster" "alveum_redis" {
  cluster_id = "alveum-redis"
  engine = "redis"
  node_type = "cache.t3.micro"
  num_cache_nodes = 1
  parameter_group_name = "default.redis6.x"
  engine_version = "6.x"
  port = 6379
  subnet_group_name = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids = [aws_security_group.redis_sg.id]
}

# 4. Create Lambda functions
resource "aws_lambda_function" "core_service_lambda" {
  function_name = "CoreServiceLambda"
  handler = "index.handler"
  runtime = "nodejs18.x"
  role = aws_iam_role.lambda_exec_role.arn
  filename = "core_service_lambda.zip"
  source_code_hash = filebase64sha256("core_service_lambda.zip")
  vpc_config {
    subnet_ids = aws_subnet.private_subnet[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  environment {
    variables = {
      DB_PROXY_ENDPOINT = aws_db_proxy.alveum_db_proxy.endpoint
      REDIS_ENDPOINT = aws_elasticache_cluster.alveum_redis.cache_nodes[0].address
    }
  }
}

resource "aws_lambda_function" "logging_service_lambda" {
  function_name = "LoggingServiceLambda"
  handler = "index.handler"
  runtime = "nodejs18.x"
  role = aws_iam_role.lambda_exec_role.arn
  filename = "logging_service_lambda.zip"
  source_code_hash = filebase64sha256("logging_service_lambda.zip")
  vpc_config {
    subnet_ids = aws_subnet.private_subnet[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

resource "aws_lambda_function" "external_api_lambda" {
  function_name = "ExternalApiLambda"
  handler = "index.handler"
  runtime = "nodejs18.x"
  role = aws_iam_role.lambda_exec_role.arn
  filename = "external_api_lambda.zip"
  source_code_hash = filebase64sha256("external_api_lambda.zip")
}

# 5. Create API Gateway
resource "aws_api_gateway_rest_api" "alveum_api" {
  name = "AlveumAPI"
}

resource "aws_api_gateway_resource" "external_resource" {
  rest_api_id = aws_api_gateway_rest_api.alveum_api.id
  parent_id = aws_api_gateway_rest_api.alveum_api.root_resource_id
  path_part = "external"
}

resource "aws_api_gateway_method" "external_method" {
  rest_api_id = aws_api_gateway_rest_api.alveum_api.id
  resource_id = aws_api_gateway_resource.external_resource.id
  http_method = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "external_integration" {
  rest_api_id = aws_api_gateway_rest_api.alveum_api.id
  resource_id = aws_api_gateway_resource.external_resource.id
  http_method = aws_api_gateway_method.external_method.http_method
  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = aws_lambda_function.external_api_lambda.invoke_arn
}

# 6. Outputs
output "api_gateway_url" {
  value = aws_api_gateway_deployment.alveum_api_deployment.invoke_url
}