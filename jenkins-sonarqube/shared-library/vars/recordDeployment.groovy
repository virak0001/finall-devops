// Record one deployment event — who, what, where, and how it ended — in
// CloudWatch Logs, at /upskill-devops/deployments, one stream per environment.
//
//   recordDeployment(environment: 'prod', service: 'auth-api', tag: t,
//                    status: 'SUCCEEDED', initiator: who, ...)
//
// status is one of:
//   SUCCEEDED     the new version is Healthy and passed its smoke test
//   FAILED        it did not, and nothing was rolled back (dev)
//   ROLLED_BACK   it did not, and the previous version is running again
//   ROLLBACK_FAILED  neither version is healthy — page someone
//   BUILD_FAILED  the pipeline stopped before deploying (tests, scans, gates)
//
// Query the history from anywhere with the AWS CLI or Logs Insights:
//
//   fields @timestamp, environment, service, tag, status, initiator
//   | filter environment = "prod" | sort @timestamp desc
//
// Terraform (global/deployments.tf) turns FAILED, ROLLED_BACK,
// ROLLBACK_FAILED and BUILD_FAILED into a metric with an alarm on it.
//
// Never fails the build. A deploy that worked is not undone because its
// record could not be written; the gap is printed instead.

def call(Map e) {
  def c = platform.cfg()
  def event = [
    timestamp   : new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC')),
    environment : e.environment ?: 'none',
    service     : e.service,
    team        : e.team,
    action      : e.action ?: 'deploy',
    status      : e.status,
    tag         : e.tag,
    image       : e.tag ? platform.image(e.service, e.tag) : null,
    previousTag : e.previousTag,
    initiator   : e.initiator,
    sourceCommit: e.source,
    gitopsCommit: e.gitopsCommit,
    detail      : e.detail,
    job         : env.JOB_NAME,
    build       : env.BUILD_NUMBER,
    buildUrl    : env.BUILD_URL,
  ]

  String json = toJson(event)
  echo "deployment record: ${json}"
  writeFile file: '.platform/deployment.json', text: json + '\n'
  archiveArtifacts artifacts: '.platform/deployment.json', allowEmptyArchive: true

  try {
    writeFile file: '.platform/log-events.json',
              text: toJson([[timestamp: System.currentTimeMillis(), message: json]])
    String stream = event.environment
    // The stream may not exist yet; creating one that does is the only error
    // that is fine to swallow here.
    runTool('awsCli', "logs create-log-stream --log-group-name '${c.deploymentsLogGroup}' --log-stream-name '${stream}'",
         returnStatus: true)
    runTool('awsCli', "logs put-log-events --log-group-name '${c.deploymentsLogGroup}' --log-stream-name '${stream}' " +
                   "--log-events file://.platform/log-events.json --output text --query rejectedLogEventsInfo")
  } catch (err) {
    echo "WARNING: could not write the deployment record to CloudWatch (${err}). It is archived with this build."
  }
}

@NonCPS
String toJson(Object o) {
  return groovy.json.JsonOutput.toJson(o)
}
