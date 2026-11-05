// The pipeline every service repository runs. Its whole Jenkinsfile is:
//
//   @Library('platform') _
//   servicePipeline(service: 'auth-api', team: 'api-service',
//                   sonarCredentialsId: 'sonar-auth-service-token',
//                   smokePaths: ['/api/auth/health'])
//
// Every branch and pull request — CI, nothing leaves Jenkins:
//
//   checkout → secret scan → unit tests → SonarQube + quality gate → build →
//   security scan (dependencies + image)
//
// The three environment branches, additionally — deploy:
//
//   develop → dev    push to ECR → commit the tag → Argo CD → smoke test → record
//   testing → uat    the same, and rolls back by itself if the checks fail
//   main    → prod   the same, after an approval (prodApprovers)
//
// The image is keyed by the commit, not the branch. Merging develop → testing →
// main by fast-forward moves the SAME commit, whose image is already in ECR, so
// uat and prod run exactly the image dev tested — it is not rebuilt. A merge
// commit is a new commit, and gets a new image.
//
// Image tag: `git describe` of the commit — "3.0.6-2-g73bf736" is two commits
// after release v3.0.6, at 73bf736. Versioned, unique per commit, and ECR's
// immutable tags guarantee it only ever names one image. A rebuild of a
// commit already in ECR skips straight to the deploy.
//
// Options:
//   service            ECR repository and Helm service name (required)
//   team               namespace / Argo CD project (required)
//   sonarCredentialsId Jenkins credential with the SonarQube token (required)
//   smokePaths         public paths that must answer 2xx/3xx after a deploy
//   branches           branch → environment; default
//                      [develop: 'dev', testing: 'uat', main: 'prod']
//   prodApprovers      Jenkins user ids who may approve prod (default 'admin')
//   securityGate       severities that fail the build: 'CRITICAL' (default)
//                      or 'HIGH,CRITICAL'. Unfixed findings never fail it.

def call(Map cfg) {
  ['service', 'team', 'sonarCredentialsId'].each { k ->
    if (!cfg[k]) { error("servicePipeline: '${k}' is required") }
  }
  Map branches = cfg.branches ?: [develop: 'dev', testing: 'uat', main: 'prod']
  String approvers = cfg.prodApprovers ?: 'admin'
  String gate = cfg.securityGate ?: 'CRITICAL'
  List smokePaths = cfg.smokePaths ?: []

  pipeline {
    agent any

    options {
      disableConcurrentBuilds()
      buildDiscarder(logRotator(numToKeepStr: '30'))
      timeout(time: 45, unit: 'MINUTES')
      timestamps()
    }

    environment {
      SERVICE = "${cfg.service}"
      TEAM    = "${cfg.team}"
    }

    stages {

      stage('Prepare') {
        steps {
          script {
            env.DEPLOY_ENV = env.CHANGE_ID ? '' : (branches[env.BRANCH_NAME] ?: '')
            env.IS_DEPLOY = env.DEPLOY_ENV ? 'true' : 'false'
            env.INITIATOR = initiator()
            env.SHORT_SHA = env.GIT_COMMIT.take(7)

            // Releases are tags vMAJOR.MINOR.PATCH on the repository. Before
            // the first one, versions count from 0.0.0.
            String described = runTool('git',
              "describe --tags --long --match 'v[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null || true",
              returnStdout: true,
              dockerArgs: "-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*'")
            String version = described ? described.replaceFirst(/^v/, '') : "0.0.0-0-g${env.SHORT_SHA}"

            // Branch and PR builds never reach ECR; their tag only has to be
            // unique on this node.
            env.IMAGE_TAG = env.IS_DEPLOY == 'true' ? version : "ci-${env.BUILD_TAG}".replaceAll(/[^A-Za-z0-9_.-]/, '-').take(120)
            env.IMAGE = platform.image(cfg.service, env.IMAGE_TAG)

            env.ALREADY_BUILT = 'false'
            if (env.IS_DEPLOY == 'true') {
              int found = runTool('awsCli',
                "ecr describe-images --repository-name '${platform.repository(cfg.service)}' --image-ids imageTag='${env.IMAGE_TAG}'",
                returnStatus: true, dockerArgs: '--entrypoint aws')
              env.ALREADY_BUILT = found == 0 ? 'true' : 'false'
            }

            currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.IMAGE_TAG}"
            currentBuild.description = "by ${env.INITIATOR}"
            echo """
              service    : ${cfg.service} (team ${cfg.team})
              branch     : ${env.BRANCH_NAME}${env.CHANGE_ID ? " (PR #${env.CHANGE_ID})" : ''}
              commit     : ${env.GIT_COMMIT}
              image      : ${env.IMAGE}
              started by : ${env.INITIATOR}
              deploys    : ${env.IS_DEPLOY == 'true' ? "yes — to ${env.DEPLOY_ENV}" : 'no (CI only)'}${env.ALREADY_BUILT == 'true' ? ' — image already in ECR, not rebuilt' : ''}
            """.stripIndent()
          }
        }
      }

      // ── Source checks ──────────────────────────────────────────────────────

      stage('Secret scan') {
        steps {
          script {
            int rc = runTool('gitleaks',
              'detect --source="$WORKSPACE" --log-opts=HEAD --redact --no-banner --exit-code 42 ' +
              '--report-format json --report-path "$WORKSPACE/gitleaks-report.json"',
              returnStatus: true,
              dockerArgs: "-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*'")
            if (rc == 42) {
              error('Gitleaks found committed secrets — see gitleaks-report.json in the build artifacts. ' +
                    'Rotate the credential first: it is in git history and must be treated as leaked. ' +
                    'Then rewrite the history, or allowlist the fingerprint in .gitleaksignore.')
            }
            if (rc != 0) {
              error("Gitleaks failed to run (exit ${rc}) — a broken scan, not a clean one.")
            }
          }
        }
        post { always { archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true } }
      }

      stage('Unit tests') {
        steps {
          // test:cov where the repo defines it — it writes coverage/lcov.info,
          // which SonarQube reads next. A repo without one skips the stage
          // entirely, npm ci included: client-side has no tests, and its
          // lockfile only installs with the npm its Dockerfile pins (11.x),
          // so a bare `npm ci` here would fail the build for nothing.
          runTool('node', '''bash -c 'if node -e "process.exit(require(\\"./package.json\\").scripts?.[\\"test:cov\\"] ? 0 : 1)"; then npm ci --no-audit --no-fund && npm run test:cov -- --passWithNoTests; else echo "no test:cov script in package.json — no unit tests to run"; fi' ''',
               dockerArgs: '--entrypoint ""')
        }
      }

      stage('SonarQube') {
        steps {
          // withSonarQubeEnv records the analysis task id that the quality
          // gate below waits on — without it: "Unable to get SonarQube task id".
          //
          // --network ci_default: the scanner is a sibling container, and
          // "sonarqube" only resolves on the compose network.
          withSonarQubeEnv('SonarQube') {
            withCredentials([string(credentialsId: cfg.sonarCredentialsId, variable: 'SONAR_TOKEN')]) {
              runTool('sonar',
                '-Dsonar.projectBaseDir="$WORKSPACE" -Dsonar.working.directory="$WORKSPACE/.scannerwork" ' +
                '-Dsonar.projectVersion="$IMAGE_TAG"',
                dockerArgs: '--network ci_default --user root -e SONAR_HOST_URL -e SONAR_TOKEN')
            }
          }
        }
      }

      stage('Quality gate') {
        steps {
          timeout(time: 10, unit: 'MINUTES') {
            waitForQualityGate abortPipeline: true
          }
        }
      }

      // ── Image ──────────────────────────────────────────────────────────────

      stage('Build image') {
        when { environment name: 'ALREADY_BUILT', value: 'false' }
        steps {
          // Who, what and from where, inside the image itself:
          //   docker inspect <image> --format '{{json .Config.Labels}}'
          sh '''
            docker build \
              --label org.opencontainers.image.revision="$GIT_COMMIT" \
              --label org.opencontainers.image.version="$IMAGE_TAG" \
              --label org.opencontainers.image.created="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              --label io.upskill.built-by="$INITIATOR" \
              --label io.upskill.build-url="$BUILD_URL" \
              -t "$IMAGE" .
          '''
        }
      }

      stage('Security scan') {
        steps {
          script {
            // Trivy, twice over the same rule:
            //   dependencies  the repo's lockfiles, dev dependencies included
            //   image         base image and OS packages, which the lockfile
            //                 cannot see — only when this build made the image
            //
            // Each target is scanned ONCE, every severity, to JSON. The report
            // is rendered from that JSON by resources/platform/trivy-report.tpl:
            // worst first (CRITICAL → HIGH → MEDIUM → LOW), with ✗ on each
            // finding that blocks. It is printed and archived as
            // trivy-<target>.txt, beside the raw trivy-<target>.json.
            //
            // A finding blocks when its severity is in `gate` AND a fix
            // exists. One with no fix cannot be acted on, so it must not block
            // every release. Accepted risks go in .trivyignore, one CVE per
            // line, with a comment saying why — the scan drops them before
            // the report, so they neither show nor block.
            //
            // Both targets are reported before the stage fails, so one red
            // build shows everything to fix. A scanner that could not run (no
            // DB, no image) fails as broken, never as clean.
            writeFile file: '.platform/trivy-report.tpl',
                      text: libraryResource('platform/trivy-report.tpl').replace('__GATE__', trivyList(gate))

            String cache = '-v trivy-cache:/root/.cache/trivy'
            List scans = [[name: 'dependencies', args: 'fs --scanners vuln --skip-dirs node_modules .',
                           docker: cache]]
            if (env.ALREADY_BUILT == 'false') {
              scans << [name: 'image', args: 'image "$IMAGE"',
                        docker: "-v /var/run/docker.sock:/var/run/docker.sock ${cache}"]
            }

            List blocked = []
            String dbUpdate = ''   // the first scan refreshes the DB; the next reuses it
            for (Map s : scans) {
              int rc = runTool('trivy',
                "${s.args} ${dbUpdate} --format json --output trivy-${s.name}.json --exit-code 0 --no-progress",
                returnStatus: true, dockerArgs: s.docker)
              if (rc != 0) { error("Trivy ${s.name} scan failed to run (exit ${rc}) — a broken scan, not a clean one.") }
              dbUpdate = '--skip-db-update'

              rc = runTool('trivy',
                "convert --format template --template @.platform/trivy-report.tpl --output trivy-${s.name}.txt trivy-${s.name}.json",
                returnStatus: true)
              if (rc != 0) { error("Trivy ${s.name} report failed to render (exit ${rc}).") }

              String report = readFile("trivy-${s.name}.txt")
              echo "══ Security scan: ${s.name} — blocks on fixable ${gate} ══\n${report}"
              int blocking = blockingCount(report)
              if (blocking < 0) { error("Trivy ${s.name} report has no 'blocking:' line — the template is broken.") }
              if (blocking > 0) { blocked << "${s.name} (${blocking})" }
            }

            if (blocked) {
              error("Fixable ${gate} vulnerabilities in: ${blocked.join(', ')} — marked ✗ in the report above. " +
                    'Upgrade the package or base image, or accept the risk in .trivyignore with a comment saying why.')
            }
          }
        }
        post { always { archiveArtifacts artifacts: 'trivy-*.txt, trivy-*.json', allowEmptyArchive: true } }
      }

      stage('Push to ECR') {
        when {
          allOf {
            environment name: 'IS_DEPLOY', value: 'true'
            environment name: 'ALREADY_BUILT', value: 'false'
          }
        }
        steps {
          // The repository already exists — Terraform's (global/). The
          // instance profile may push to upskill-devops/* and create nothing.
          sh """
            ${awsCmd()} ecr get-login-password | docker login --username AWS --password-stdin '${platform.registry()}'
            docker push "\$IMAGE"
            docker logout '${platform.registry()}'
          """
        }
      }

      // ── Deploy ─────────────────────────────────────────────────────────────

      stage('Approve prod') {
        when { environment name: 'DEPLOY_ENV', value: 'prod' }
        steps {
          script {
            notifyTelegram('WAITING FOR APPROVAL', '⏳', "${cfg.service} ${env.IMAGE_TAG} → prod\nby ${env.INITIATOR}")
            timeout(time: 60, unit: 'MINUTES') {
              // The approver's user id comes back, and is who the prod
              // release is recorded against.
              env.APPROVER = input(message: "Deploy ${cfg.service} ${env.IMAGE_TAG} to PRODUCTION?",
                                   ok: 'Deploy to prod', submitter: approvers,
                                   submitterParameter: 'APPROVER')
            }
            env.DEPLOY_AUTHOR = "${env.APPROVER} <${env.APPROVER}@jenkins.local>"
            env.INITIATOR = "${env.APPROVER} (approved; pushed by ${env.INITIATOR})"
          }
        }
      }

      stage('Deploy') {
        when { environment name: 'IS_DEPLOY', value: 'true' }
        steps {
          script {
            // dev keeps a failed release in place, so it can be looked at;
            // uat and prod put the previous version back by themselves.
            deploy(environment: env.DEPLOY_ENV, service: cfg.service, team: cfg.team, tag: env.IMAGE_TAG,
                   smokePaths: smokePaths, initiator: env.INITIATOR,
                   source: "${env.GIT_URL ?: cfg.service}@${env.GIT_COMMIT}",
                   action: 'deploy', rollbackOnFailure: env.DEPLOY_ENV != 'dev',
                   reason: "Built from ${env.BRANCH_NAME} @ ${env.SHORT_SHA} by ${env.INITIATOR}")
          }
        }
      }
    }

    post {
      success {
        script {
          notifyTelegram('SUCCESS', '✅', "${cfg.service} ${env.IMAGE_TAG ?: ''}" +
            (env.IS_DEPLOY == 'true' ? " → ${env.DEPLOY_ENV}" : ' (CI)') + "\nby ${env.INITIATOR ?: 'unknown'}")
        }
      }
      failure {
        script {
          // A failure before the deploy stage never reached recordDeployment;
          // record it here so failed pipelines are in the same history and
          // feed the same alarm.
          if (!fileExists('.platform/deployment.json')) {
            recordDeployment(environment: env.DEPLOY_ENV ?: 'ci', service: cfg.service,
                             team: cfg.team, tag: env.IMAGE_TAG, status: 'BUILD_FAILED',
                             initiator: env.INITIATOR, source: "${env.GIT_URL ?: cfg.service}@${env.GIT_COMMIT}",
                             detail: "stage failed on ${env.BRANCH_NAME}")
          }
          notifyTelegram('FAILED', '❌', "${cfg.service} ${env.IMAGE_TAG ?: ''}\nby ${env.INITIATOR ?: 'unknown'}")
        }
      }
      aborted { script { notifyTelegram('CANCELLED', '⛔', cfg.service) } }
      // cleanup, not always: Jenkins runs `always` FIRST, before failure{},
      // which then could not see .platform/deployment.json and wrote a
      // second, wrong BUILD_FAILED record. cleanup runs last.
      cleanup {
        // Scoped to this build. A global prune would delete layers another
        // job's build is still writing (see the old Jenkinsfiles' history).
        sh '''
          docker rmi "$IMAGE" 2>/dev/null || true
          docker image prune -f >/dev/null 2>&1 || true
          rm -rf node_modules coverage .scannerwork .platform .gitops trivy-*.json trivy-*.txt
        '''
      }
    }
  }
}

// "CRITICAL,HIGH" → "CRITICAL" "HIGH", a list literal for the report template.
// @NonCPS: plain string work, and closures inside CPS code are fragile.
@NonCPS
String trivyList(String severities) {
  return severities.split(',').collect { "\"${it.trim().toUpperCase()}\"" }.join(' ')
}

// The template's last line is "blocking: N". -1 when it is missing.
@NonCPS
int blockingCount(String report) {
  def m = report =~ /(?m)^blocking: (\d+)\s*$/
  return m.find() ? (m.group(1) as int) : -1
}

// The aws CLI as a shell command, for use inside a larger `sh` — piping into
// docker login does not fit runTool().
String awsCmd() {
  return "docker run --rm -e AWS_DEFAULT_REGION=${platform.cfg().awsRegion} ${platform.toolImage('awsCli')}"
}
