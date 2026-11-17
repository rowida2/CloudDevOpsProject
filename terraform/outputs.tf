output "ecr_urls" {
  value = module.ecr.repository_urls
}

output "jenkins_public_ip" {
  value = module.server.public_ip
}