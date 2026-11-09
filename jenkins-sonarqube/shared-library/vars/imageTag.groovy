// Image names — one scheme for every service, and the ECR side of it.
//
// One image per commit, built once. It gains a name per environment it
// reaches; it is never rebuilt for one:
//
//   dev-5a87e72    built from develop (the commit, 7 characters)
//   uat-5a87e72    the SAME image, named when it reaches uat
//   prod-v1.0.8    the SAME image, named when it is released — the git tag
//
// A name is added, never moved. Adding one puts the same manifest under a new
// tag, so every name of an image has one digest, and ECR's immutable tags mean
// a name can never later point somewhere else.
//
//   imageTag.forEnv('uat', sha, null)          → 'uat-5a87e72'
//   imageTag.forEnv('prod', sha, 'v1.0.8')     → 'prod-v1.0.8'
//   imageTag.shaOf('uat-5a87e72')              → '5a87e72'
//   imageTag.find('auth-api', 'dev-5a87e72')   → [digest: 'sha256:…', tags: [...]] or null
//   imageTag.add('auth-api', 'dev-5a87e72', 'uat-5a87e72')
//   imageTag.releaseVersion('auth-api', sha)   → 'v1.0.8' or null

// version: the release (vX.Y.Z) for prod, null otherwise.
String forEnv(String environment, String sha, String version) {
  if (environment == 'prod') {
    if (!isRelease(version)) {
      error("imageTag.forEnv(): prod needs a vX.Y.Z release version, got '${version}'")
    }
    return "prod-${version}"
  }
  if (!(environment in ['dev', 'uat'])) {
    error("imageTag.forEnv(): no environment '${environment}'")
  }
  return "${environment}-${sha.take(7)}"
}

// The commit an image name was built from, or null when the name does not
// say (a prod- name, or an older scheme). Also reads the tags the pipeline
// used before this scheme — `git describe` output, 1.0.7-14-g5a87e72.
@NonCPS
String shaOf(String tag) {
  def m = tag =~ /^(?:dev|uat)-([0-9a-f]{7,40})$/
  if (m.find()) {
    return m.group(1).take(7)
  }
  m = tag =~ /-g([0-9a-f]{7,40})$/
  return m.find() ? m.group(1).take(7) : null
}

@NonCPS
boolean isRelease(String version) {
  return version ==~ /v\d+\.\d+\.\d+/
}

// The other commit an image already belongs to, judged by its other names —
// or null when it is this commit's image, or nothing says either way.
@NonCPS
String otherCommit(Map image, String sha) {
  def other = image.tags.collect { shaOf(it) }.find { it && it != sha.take(7) }
  return other
}

Map find(String service, String tag) {
  Map r = ecr("find '${platform.repository(service)}' '${tag}'")
  if (r.found != 'true') {
    return null
  }
  return [digest: r.digest, tags: (r.tags ?: '').tokenize(',')]
}

void add(String service, String fromTag, String toTag) {
  ecr("add '${platform.repository(service)}' '${fromTag}' '${toTag}'")
}

// The vX.Y.Z tag on a commit of the service's repository, or null. For the
// promote job, which has the image's commit but not the repository.
String releaseVersion(String service, String sha) {
  def c = platform.cfg()
  String repo = c.serviceRepos[service]
  if (!repo) {
    error("imageTag.releaseVersion(): no repository for '${service}' in platform.cfg().serviceRepos")
  }
  writeFile file: '.platform/release-tag.sh', text: libraryResource('platform/release-tag.sh')
  sh 'rm -f .platform/release.env'
  withCredentials([usernamePassword(credentialsId: c.serviceRepoCredentialsId,
                                    usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
    withEnv(["RELEASE_REPO=${repo}"]) {
      // -e NAME with no value passes the variable through, so the token is
      // never on a command line.
      runTool('k8s', "bash .platform/release-tag.sh '${sha.take(7)}'",
              dockerArgs: '-e GH_USER -e GH_TOKEN -e REPO="$RELEASE_REPO" --entrypoint ""')
    }
  }
  String v = gitops.parseResult(readFile('.platform/release.env')).version
  return v ?: null
}

Map ecr(String args) {
  writeFile file: '.platform/ecr-image.sh', text: libraryResource('platform/ecr-image.sh')
  sh 'rm -f .platform/ecr.env'
  runTool('awsCli', "bash .platform/ecr-image.sh ${args}", dockerArgs: '--entrypoint ""')
  return gitops.parseResult(readFile('.platform/ecr.env'))
}
