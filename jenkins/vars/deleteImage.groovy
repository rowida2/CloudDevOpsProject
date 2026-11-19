def call(String imageName, String imageTag, String registry) {
    sh "docker rmi ${imageName}:${imageTag} ${registry}/${imageName}:${imageTag} || true"
}