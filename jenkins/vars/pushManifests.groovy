def call(String repoUrl, String branch, String commitMsg) {
    withCredentials([usernamePassword(credentialsId: 'github-creds',
                                      usernameVariable: 'GIT_USER',
                                      passwordVariable: 'GIT_TOKEN')]) {
        sh """
          git config user.email "jenkins@ivolve.local"
          git config user.name "Jenkins"
          git add k8s/
          git commit -m "${commitMsg}" || echo "No changes to commit"
          git push https://\${GIT_USER}:\${GIT_TOKEN}@${repoUrl.replace('https://','')} HEAD:${branch}
        """
    }
}