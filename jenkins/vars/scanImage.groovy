def call(String imageName, String imageTag) {
   
    sh "trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed ${imageName}:${imageTag}"
}