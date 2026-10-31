// Run one of the pinned tool images against this build's workspace.
//
// Named runTool, not tool: Jenkins has a built-in `tool` step, and a
// declarative pipeline resolves a bare tool(...) to it — failing with
// "Arguments to \"tool\" must be explicitly named".
//
//   runTool('trivy', 'fs --exit-code 1 .')
//   runTool('awsCli', 'ecr describe-images ...', returnStdout: true)
//
// Jenkins runs in a container and reaches Docker through the host's socket,
// so a tool container is a SIBLING of Jenkins, not a child. Two consequences
// shape the flags below:
//
//   --volumes-from jenkins   the workspace is inside the Jenkins container's
//                            volume; a bind mount of $WORKSPACE would mount the
//                            HOST path of that name, which is empty
//   -w "$WORKSPACE"          so relative paths mean what they mean in `sh`
//
// AWS credentials are never passed: the AWS CLI in a container falls through
// to the instance profile via IMDS (the instance's hop limit is 2 for this).
//
// Arguments are shell text — quote them as you would in `sh`.

def call(Map opts = [:], String name, String args) {
  String cmd = """docker run --rm --volumes-from jenkins -w "\$WORKSPACE" \
    -e AWS_DEFAULT_REGION=${platform.cfg().awsRegion} ${opts.dockerArgs ?: ''} \
    ${platform.toolImage(name)} ${args}"""

  if (opts.returnStdout) {
    return sh(script: cmd, returnStdout: true).trim()
  }
  if (opts.returnStatus) {
    return sh(script: cmd, returnStatus: true)
  }
  sh cmd
}
