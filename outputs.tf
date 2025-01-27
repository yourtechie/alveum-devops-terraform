output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = aws_api_gateway_deployment.alveum_api_deployment.invoke_url
}