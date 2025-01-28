
# **Alveum DevOps System - Terraform Deployment**

This repository contains the Terraform configuration to deploy a scalable and secure microservices-based system on AWS. The system includes:

1. **Core Service**: A Node.js/TypeScript AWS Lambda function that interacts with AWS RDS (via RDS Proxy) and ElasticCache.
2. **Logging Service**: A Node.js/TypeScript AWS Lambda function that publishes logs to Amazon CloudWatch.
3. **External API Service**: A Node.js/TypeScript AWS Lambda function deployed outside the VPC that interacts with external APIs.
4. **API Gateway**: Serves as the entry point for the services.
5. **Database**: AWS RDS (PostgreSQL) with RDS Proxy for connection pooling.
6. **Cache Layer**: AWS ElasticCache (Redis) for caching.
7. **Networking**: A VPC with public and private subnets for secure communication.

---

## **Design Choices**

### **1. VPC Design**
- **Public Subnets**: Used for resources that need to be publicly accessible (e.g., API Gateway).
- **Private Subnets**: Used for internal resources (e.g., RDS, ElasticCache, Lambda functions).
- **NAT Gateway**: Allows resources in private subnets to access the internet (e.g., for external API calls).

### **2. Database**
- **RDS PostgreSQL**: A relational database for structured data storage.
- **RDS Proxy**: Manages database connections efficiently, enabling connection pooling and reducing the load on the database.

### **3. Caching**
- **ElasticCache (Redis)**: Used to cache frequently accessed data, reducing the load on the database and improving performance.

### **4. Lambda Functions**
- **Core Service**: Handles business logic and interacts with RDS and ElasticCache.
- **Logging Service**: Publishes logs to CloudWatch for monitoring and debugging.
- **External API Service**: Deployed outside the VPC to interact with external APIs.

### **5. API Gateway**
- Serves as the entry point for the system, routing requests to the appropriate Lambda functions.

### **6. Security**
- **IAM Roles**: Least privilege roles are assigned to Lambda functions.
- **Security Groups**: Restrict access to RDS, ElasticCache, and Lambda functions.
- **Secrets Manager**: Stores sensitive credentials (e.g., database credentials).

### **7. Scalability**
- **AWS Lambda**: Automatically scales with demand.
- **RDS Proxy**: Ensures efficient database connection pooling.
- **ElasticCache**: Improves performance by caching frequently accessed data.

---

## **Prerequisites**

1. **AWS Account**: Ensure you have an AWS account with the necessary permissions.
2. **AWS CLI**: Install and configure the AWS CLI with your credentials.
   ```bash
   aws configure
   ```
3. **Terraform**: Install Terraform from [here](https://learn.hashicorp.com/tutorials/terraform/install-cli).
4. **Node.js**: Install Node.js (v18.x or later) for Lambda function development.

---

## **Deployment Instructions**

### **1. Clone the Repository**
```bash
git clone https://github.com/yourtechie/alveum-devops-terraform.git
cd alveum-devops-terraform
```

### **2. Initialize Terraform**
```bash
terraform init
```

### **3. Review the Plan**
```bash
terraform plan
```

### **4. Apply the Configuration**
```bash
terraform apply
```
- Confirm the deployment by typing `yes` when prompted.

### **5. Access the System**
- After deployment, Terraform will output the API Gateway URL. Use this URL to interact with the system.

---

## **Next Steps**
1. **Add RabbitMQ Integration**:
   - Store RabbitMQ credentials in AWS Secrets Manager.
   - Update the Core Service Lambda function to consume messages from RabbitMQ.

2. **Set Up CI/CD Pipeline**:
   - Use AWS CodePipeline and CodeBuild to automate the deployment process.

3. **Add Monitoring**:
   - Set up CloudWatch Alarms and Dashboards for monitoring.

---

## **Steps to Automate the Deployment Process**
To avoid manual steps, we can set up a **CI/CD pipeline** using **AWS CodePipeline** and **CodeBuild**. Here’s an example pipeline configuration:

### **1. Create a `buildspec.yml` File**
This file defines the build steps for CodeBuild:
```yaml
version: 0.2

phases:
  install:
    commands:
      - echo "Installing dependencies..."
      - npm install -g aws-cdk
      - terraform init

  build:
    commands:
      - echo "Building the infrastructure..."
      - terraform validate
      - terraform apply -auto-approve

artifacts:
  files:
    - "**/*"
```

### **2. Create a CodePipeline**
Use the following Terraform configuration to create a pipeline:

```hcl
resource "aws_codepipeline" "alveum_pipeline" {
  name     = "alveum-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner      = "your-github-username"
        Repo       = "your-repo-name"
        Branch     = "main"
        OAuthToken = var.github_token
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.alveum_build.name
      }
    }
  }
}

resource "aws_codebuild_project" "alveum_build" {
  name          = "alveum-build"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}
```

## **Cleanup**
To avoid unnecessary charges, destroy the infrastructure after testing:
```bash
terraform destroy
```

---