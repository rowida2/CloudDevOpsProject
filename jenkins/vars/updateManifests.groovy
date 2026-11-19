def call(String manifestFile, String fullImage) {
   
    sh "sed -i 's|image:.*|image: ${fullImage}|' ${manifestFile}"
}