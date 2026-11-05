// The prod approval, run inside the Deploy stage rather than as a stage of
// its own: a declarative pipeline draws every stage it declares, so a
// separate "Approve prod" stage showed as skipped on every dev and uat build.
//
//   approveProd(message: 'Deploy client-side 1.0.7 to PRODUCTION?',
//               ok: 'Deploy to prod', submitters: 'admin',
//               notice: 'client-side 1.0.7 → prod', requestedBy: 'pushed')
//
// Waits up to 60 minutes for one of `submitters` (Jenkins user ids, comma
// separated). The approver then becomes the deployer of record:
//   env.APPROVER       their user id
//   env.DEPLOY_AUTHOR  author of the cluster-repo commit
//   env.INITIATOR      "<approver> (approved; <requestedBy> by <initiator>)"

def call(Map a) {
  notifyTelegram('WAITING FOR APPROVAL', '⏳', "${a.notice}\n${a.requestedBy} by ${env.INITIATOR}")
  timeout(time: 60, unit: 'MINUTES') {
    env.APPROVER = input(message: a.message, ok: a.ok, submitter: a.submitters,
                         submitterParameter: 'APPROVER')
  }
  env.DEPLOY_AUTHOR = "${env.APPROVER} <${env.APPROVER}@jenkins.local>"
  env.INITIATOR = "${env.APPROVER} (approved; ${a.requestedBy} by ${env.INITIATOR})"
}
