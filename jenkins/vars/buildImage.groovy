def call(String imageName, String imageTag, String contextDir) {
    sh "docker build -t ${imageName}:${imageTag} ${contextDir}"
}