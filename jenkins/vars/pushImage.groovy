def call(String imageName, String imageTag, String registry, String region) {
    sh """
      aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${registry}
      docker tag ${imageName}:${imageTag} ${registry}/${imageName}:${imageTag}
      docker push ${registry}/${imageName}:${imageTag}
    """
}