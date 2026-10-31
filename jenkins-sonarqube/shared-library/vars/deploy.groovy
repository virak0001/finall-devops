// Deploy one image tag to one environment, prove it works, and record it.
//
//   deploy(environment: 'uat', service: 'auth-api', team: 'api-service',
//          tag: '3.0.6-2-g73bf736', smokePaths: ['/api/auth/health'],
//          initiator: who, source: 'repo@sha', action: 'promote',
//          rollbackOnFailure: true)
//
//   1. commit the tag to helm/env/<env>.yaml in the cluster repo (gitops)
//   2. wait for Argo CD: that commit Synced, the app Healthy, the image running
//   3. smoke-test the public URLs through the ALB
//   4. on failure, with rollbackOnFailure: commit the previous tag back, wait
//      for it the same way — the automated version of `git revert` + sync
//   5. record the outcome (recordDeployment) and fail the build if it failed
//
// prod is synced by this step after the approval that precedes it; dev and
// uat sync themselves, and this only waits for them.

def call(Map d) {
  String image = platform.image(d.service, d.tag)
  def record = [environment: d.environment, service: d.service, team: d.team, tag: d.tag,
                action: d.action ?: 'deploy', initiator: d.initiator, source: d.source]

  def r = gitops.setTag(environment: d.environment, service: d.service, tag: d.tag,
                        action: record.action, initiator: d.initiator, source: d.source,
                        reason: d.reason)
  record.previousTag = r.previousTag
  record.gitopsCommit = r.commit

  String problem = verify(d.environment, d.team, r.commit, image, d.smokePaths ?: [])
  if (!problem) {
    recordDeployment(record + [status: 'SUCCEEDED'])
    return r
  }

  if (!(d.rollbackOnFailure && r.changed && r.previousTag)) {
    recordDeployment(record + [status: 'FAILED', detail: problem])
    error("${d.service} ${d.tag} in ${d.environment}: ${problem}. Left in place — nothing rolled back.")
  }

  echo "${d.service} ${d.tag} failed in ${d.environment} (${problem}) — rolling back to ${r.previousTag}"
  def rb = gitops.setTag(environment: d.environment, service: d.service, tag: r.previousTag,
                         action: 'rollback', initiator: 'jenkins (automatic)', source: d.source,
                         reason: "Automatic rollback: ${d.tag} failed verification — ${problem}")
  String rbProblem = verify(d.environment, d.team, rb.commit, platform.image(d.service, r.previousTag), d.smokePaths ?: [])

  if (rbProblem) {
    recordDeployment(record + [status: 'ROLLBACK_FAILED', gitopsCommit: rb.commit,
                               detail: "${problem}; rollback to ${r.previousTag} also failed: ${rbProblem}"])
    error("${d.service} in ${d.environment}: ${d.tag} failed AND the rollback to ${r.previousTag} failed (${rbProblem}). Investigate now.")
  }
  recordDeployment(record + [status: 'ROLLED_BACK', gitopsCommit: rb.commit,
                             detail: "${problem}; ${r.previousTag} restored"])
  error("${d.service} ${d.tag} failed in ${d.environment} (${problem}). ${r.previousTag} is running again.")
}

// Returns null when the release is healthy, otherwise what went wrong.
String verify(String environment, String team, String revision, String image, List smokePaths) {
  writeFile file: '.platform/argocd-wait.sh', text: libraryResource('platform/argocd-wait.sh')
  writeFile file: '.platform/smoke.sh', text: libraryResource('platform/smoke.sh')

  String app = "${team}-${environment}"
  int waited
  withCredentials([string(credentialsId: platform.argocdTokenId(environment), variable: 'ARGOCD_TOKEN')]) {
    withEnv(["W_SERVER=${platform.argocd(environment)}", "W_APP=${app}", "W_REVISION=${revision}",
             "W_IMAGE=${image}", "W_SYNC=${environment == 'prod'}"]) {
      waited = runTool('k8s', 'bash .platform/argocd-wait.sh', returnStatus: true,
                    dockerArgs: '-e ARGOCD_TOKEN -e ARGOCD_SERVER="$W_SERVER" -e APP="$W_APP" ' +
                                '-e REVISION="$W_REVISION" -e IMAGE="$W_IMAGE" -e SYNC="$W_SYNC" --entrypoint ""')
    }
  }
  if (waited == 2) {
    return "Argo CD did not report ${app} Healthy at ${revision.take(8)} in time"
  }
  if (waited != 0) {
    return "Argo CD reports ${app} failed or Degraded at ${revision.take(8)}"
  }

  if (smokePaths) {
    String host = platform.host(environment)
    String urls = smokePaths.collect { "'https://${host}${it}'" }.join(' ')
    int smoke = runTool('k8s', "bash .platform/smoke.sh ${urls}", returnStatus: true, dockerArgs: '--entrypoint ""')
    if (smoke != 0) {
      return 'the smoke test failed'
    }
  }
  return null
}
