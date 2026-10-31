// Who started this build, for the deployment record.
//
//   a person clicking Build       → their Jenkins user id
//   a GitHub push (webhook)       → "Name <email> (git push)", the commit's author
//   anything else (timer, replay) → the cause Jenkins gives
//
// Also sets env.DEPLOY_AUTHOR ("Name <email>"), which the GitOps commit uses
// as its git author — so GitHub's commit list and Argo CD's sync history show
// the person, with Jenkins as the committer. For prod, the approver replaces
// it (servicePipeline / promotePipeline).

String call() {
  def causes = currentBuild.getBuildCauses()
  def user = causes.find { it.userId }
  if (user) {
    env.DEPLOY_AUTHOR = "${user.userName ?: user.userId} <${user.userId}@jenkins.local>"
    return user.userId
  }
  // A webhook build's cause reads "Push event to branch develop" — it says
  // what happened, not who did it. The commit's author is the who. Matched
  // case-insensitively: Jenkins capitalises "Push", which a plain contains()
  // missed, and every push was recorded as the event text.
  if (causes.any { "${it._class ?: ''} ${it.shortDescription ?: ''}".toLowerCase().contains('push') }) {
    String author = sh(script: 'git log -1 --format="%an <%ae>" 2>/dev/null || true', returnStdout: true).trim()
    if (author) {
      env.DEPLOY_AUTHOR = author
    }
    return "${author ?: 'unknown'} (git push)"
  }
  return causes ? causes[0].shortDescription : 'unknown'
}
