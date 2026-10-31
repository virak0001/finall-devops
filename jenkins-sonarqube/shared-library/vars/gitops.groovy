// The GitOps repository, from a pipeline.
//
//   def r = gitops.setTag(environment: 'dev', service: 'auth-api', tag: t,
//                         action: 'deploy', initiator: who, source: '...')
//   r.commit        the cluster repo commit Argo CD must reach
//   r.previousTag   what was running before — the rollback target
//   r.changed       false when the tag was already there (a rebuild)
//
//   gitops.getTag('uat', 'auth-api')           what uat runs now
//   gitops.previousTag('prod', 'auth-api')     what prod ran before that
//
// A deploy is a commit to helm/env/<env>.yaml. The commit message carries the
// deployment record as git trailers, so `git log` on the cluster repo answers
// who deployed what, from where, and when — independently of Jenkins:
//
//   git log --format='%h %(trailers:key=Initiated-By,valueonly) %s' -- helm/env/prod.yaml

Map setTag(Map a) {
  def lines = [
    "${a.action ?: 'deploy'}(${a.environment}): ${a.service} ${a.tag}",
    '',
    a.reason ?: "${a.action ?: 'deploy'} ${a.service} to ${a.environment}",
    '',
    "Environment: ${a.environment}",
    "Service: ${a.service}",
    "Image: ${platform.image(a.service, a.tag)}",
    "Initiated-By: ${a.initiator ?: 'unknown'}",
  ]
  if (a.source) {
    lines << "Source-Commit: ${a.source}"
  }
  lines << "Jenkins-Build: ${env.BUILD_URL}"

  writeFile file: '.platform/commit-message.txt', text: lines.join('\n') + '\n'
  return run("set-tag ${a.environment} ${a.service} '${a.tag}' .platform/commit-message.txt")
}

String getTag(String environment, String service) {
  return run("get-tag ${environment} ${service}").tag
}

String previousTag(String environment, String service) {
  return run("previous-tag ${environment} ${service}").tag
}

// Runs resources/platform/gitops.sh in the alpine/k8s image and parses the
// KEY=value lines it writes.
Map run(String args) {
  def c = platform.cfg()
  writeFile file: '.platform/gitops.sh', text: libraryResource('platform/gitops.sh')
  sh 'rm -f .platform/result.env'

  withCredentials([usernamePassword(credentialsId: c.gitopsCredentialsId,
                                    usernameVariable: 'GH_USER',
                                    passwordVariable: 'GH_TOKEN')]) {
    // GIT_DEPLOY_AUTHOR: the person behind the deploy (initiator.groovy), as
    // the commit's author. Empty leaves git's default, jenkins.
    withEnv(["GITOPS_REPO=${c.clusterRepo}", "GITOPS_BRANCH=${c.clusterBranch}",
             "GIT_DEPLOY_AUTHOR=${env.DEPLOY_AUTHOR ?: ''}"]) {
      // -e NAME with no value passes the variable through from this shell,
      // so the token never appears on a command line.
      runTool('k8s', "bash .platform/gitops.sh ${args}",
           dockerArgs: '-e GH_USER -e GH_TOKEN -e GIT_DEPLOY_AUTHOR -e REPO="$GITOPS_REPO" -e BRANCH="$GITOPS_BRANCH" --entrypoint ""')
    }
  }
  return parseResult(readFile('.platform/result.env'))
}

// KEY_NAME=value lines → [keyName: value]. @NonCPS because it hands a closure
// to String.replaceAll, which pipeline (CPS) code cannot do.
@NonCPS
Map parseResult(String text) {
  def out = [:]
  text.split('\n').each { line ->
    def i = line.indexOf('=')
    if (i > 0) {
      def key = line.substring(0, i).toLowerCase().replaceAll(/_([a-z])/) { m -> m[1].toUpperCase() }
      out[key] = line.substring(i + 1)
    }
  }
  if (out.containsKey('changed')) {
    out.changed = (out.changed == 'true')
  }
  return out
}
