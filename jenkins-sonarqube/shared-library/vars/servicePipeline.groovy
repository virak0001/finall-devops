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
//   Every build archives security-report.txt: all four scans in one report
//   (vars/securityReport.groovy), even when the build stopped part-way.
//
// The three environment branches, additionally — publish, and deploy:
//
//   develop → dev    push to ECR → commit the tag → Argo CD → smoke test → record
//   testing → uat    the same, and rolls back by itself if the checks fail
//   main    → prod   push to ECR ONLY — Deploy is skipped. A person releases it
//                    with the `release` job (TARGET=prod), which asks for the
//                    approval. See manualDeploy below.
//
// Image names (vars/imageTag.groovy) — one image per commit, a name per
// environment it reaches:
//
//   develop → dev-5a87e72    built here, pushed to ECR
//   testing → uat-5a87e72    the SAME image: the name is added, nothing built
//   main    → prod-v1.0.8    the SAME image, named after the commit's release
//                            tag — main publishes only a commit tagged vX.Y.Z
//
// Merging develop → testing → main by fast-forward moves the SAME commit, so
// uat and prod run exactly the image dev tested. A merge commit is a new
// commit with no image yet: it is built fresh, and the build log says so.
// A rebuild of a commit that already has its name skips straight to deploy.
//
// Options:
//   service            ECR repository and Helm service name (required)
//   team               namespace / Argo CD project (required)
//   sonarCredentialsId Jenkins credential with the SonarQube token (required)
//   smokePaths         public paths that must answer 2xx/3xx after a deploy
//   branches           branch → environment; default
//                      [develop: 'dev', testing: 'uat', main: 'prod']
//   manualDeploy       environments whose branch only publishes the image and
//                      skips Deploy; default ['prod']. [] makes main deploy
//                      too, after an approval from prodApprovers.
//   prodApprovers      Jenkins user ids who may approve prod (default 'admin')
//   securityGate       severities that fail the build: 'CRITICAL' (default)
//                      or 'HIGH,CRITICAL'. Unfixed findings never fail it.

def call(Map cfg) {
  ['service', 'team', 'sonarCredentialsId'].each { k ->
    if (!cfg[k]) { error("servicePipeline: '${k}' is required") }
  }
  Map branches = cfg.branches ?: [develop: 'dev', testing: 'uat', main: 'prod']
  String approvers = cfg.prodApprovers ?: 'admin'
  List manual = cfg.manualDeploy != null ? cfg.manualDeploy : ['prod']
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
            env.IS_DEPLOY = env.DEPLOY_ENV ? 'true' : 'false'   // publishes to ECR
            env.AUTO_DEPLOY = env.DEPLOY_ENV && !(env.DEPLOY_ENV in manual) ? 'true' : 'false'
            env.INITIATOR = initiator()
            env.SHORT_SHA = env.GIT_COMMIT.take(7)

            // The version: `git describe` against the vMAJOR.MINOR.PATCH
            // release tags — 1.0.7-14-g5a87e72 is 14 commits after v1.0.7.
            // SonarQube and the image's label carry it; the image NAME is
            // per environment (below). Before the first release, 0.0.0.
            String gitEnv = "-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*'"
            String described = runTool('git',
              "describe --tags --long --match 'v[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null || true",
              returnStdout: true, dockerArgs: gitEnv)
            env.VERSION = described ? described.replaceFirst(/^v/, '') : "0.0.0-0-g${env.SHORT_SHA}"

            // prod images are releases only: the commit on main must carry a
            // vX.Y.Z tag, which names the prod image. Checked first, so a
            // missing tag costs seconds, not a full build.
            String release = ''
            if (env.DEPLOY_ENV == 'prod') {
              release = runTool('git',
                "describe --tags --exact-match --match 'v[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null || true",
                returnStdout: true, dockerArgs: gitEnv)
              if (!imageTag.isRelease(release)) {
                error("main publishes prod images only from a release, and ${env.SHORT_SHA} has no vX.Y.Z tag. " +
                      "Tag it, then run this build again:\n" +
                      "    git tag v1.2.3 ${env.SHORT_SHA} && git push origin v1.2.3")
              }
            }

            // Branch and PR builds never reach ECR; their tag only has to be
            // unique on this node.
            env.IMAGE_TAG = env.IS_DEPLOY == 'true'
              ? imageTag.forEnv(env.DEPLOY_ENV, env.GIT_COMMIT, release ?: null)
              : "ci-${env.BUILD_TAG}".replaceAll(/[^A-Za-z0-9_.-]/, '-').take(120)
            env.IMAGE = platform.image(cfg.service, env.IMAGE_TAG)

            // Is there an image already? Either under this environment's
            // name (a rebuild), or under an earlier environment's name for
            // this same commit — then it is only named, never rebuilt.
            //   ALREADY_BUILT  skip the build; the image scan pulls it from ECR
            //   REUSE_FROM     the existing name to add IMAGE_TAG to
            env.ALREADY_BUILT = 'false'
            env.REUSE_FROM = ''
            if (env.IS_DEPLOY == 'true') {
              def mine = imageTag.find(cfg.service, env.IMAGE_TAG)
              if (mine) {
                String other = imageTag.otherCommit(mine, env.SHORT_SHA)
                if (other) {
                  error("${env.IMAGE_TAG} is already the image of commit ${other}, not ${env.SHORT_SHA}. " +
                        'A release names one image forever — tag this commit with a new version.')
                }
                env.ALREADY_BUILT = 'true'
              } else {
                // uat before dev for prod: the image uat accepted. The last
                // is this commit's name from before the dev-/uat- scheme.
                List earlier = []
                for (String e : ([prod: ['uat', 'dev'], uat: ['dev']][env.DEPLOY_ENV] ?: [])) {
                  earlier << imageTag.forEnv(e, env.GIT_COMMIT, null)
                }
                earlier << env.VERSION
                for (String t : earlier) {
                  if (t != env.IMAGE_TAG && imageTag.find(cfg.service, t)) {
                    env.REUSE_FROM = t
                    env.ALREADY_BUILT = 'true'
                    break
                  }
                }
              }
            }

            currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.IMAGE_TAG}"
            currentBuild.description = "by ${env.INITIATOR}"
            echo """
              service    : ${cfg.service} (team ${cfg.team})
              branch     : ${env.BRANCH_NAME}${env.CHANGE_ID ? " (PR #${env.CHANGE_ID})" : ''}
              commit     : ${env.GIT_COMMIT}
              image      : ${env.IMAGE}
              started by : ${env.INITIATOR}
              version    : ${env.VERSION}
              deploys    : ${env.AUTO_DEPLOY == 'true' ? "yes — to ${env.DEPLOY_ENV}" : env.IS_DEPLOY == 'true' ? "no — pushed to ECR only; release it to ${env.DEPLOY_ENV} with the release job" : 'no (CI only)'}
              image from : ${env.IS_DEPLOY != 'true' ? 'this build (not pushed)' : env.REUSE_FROM ? "${env.REUSE_FROM} in ECR — the same image gets the name ${env.IMAGE_TAG}, nothing is rebuilt" : env.ALREADY_BUILT == 'true' ? 'already in ECR under this name — not rebuilt' : 'this build'}
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
                '-Dsonar.projectVersion="$VERSION"',
                dockerArgs: '--network ci_default --user root -e SONAR_HOST_URL -e SONAR_TOKEN')
            }
          }
        }
      }

      stage('Quality gate') {
        steps {
          script {
            // Not abortPipeline: the gate's conditions and issues are read
            // into the security report first, then the gate fails the build.
            def qg
            timeout(time: 10, unit: 'MINUTES') {
              qg = waitForQualityGate abortPipeline: false
            }
            securityReport.sonar(qg.status)
            echo readFile('.platform/sonar.txt')
            if (qg.status != 'OK') {
              error("SonarQube quality gate ${qg.status} — the failed conditions and the issues are above, " +
                    'and in security-report.txt in the build artifacts.')
            }
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
              --label org.opencontainers.image.version="$VERSION" \
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
            //                 cannot see. The image this build made — or, on
            //                 testing and main, where nothing is rebuilt, the
            //                 very image in ECR this build names (uat-, prod-),
            //                 pulled and scanned with TODAY's database: a CVE
            //                 published since dev built it shows here, and a
            //                 fixable one blocks the release like any other
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
            String sock = "-v /var/run/docker.sock:/var/run/docker.sock ${cache}"
            if (env.ALREADY_BUILT == 'false') {
              scans << [name: 'image', args: 'image "$IMAGE"', docker: sock]
            } else if (env.IS_DEPLOY == 'true') {
              // Its existing name: IMAGE_TAG itself is only added at Publish.
              env.SCAN_IMAGE = platform.image(cfg.service, env.REUSE_FROM ?: env.IMAGE_TAG)
              pullImage(env.SCAN_IMAGE)
              scans << [name: 'image', args: 'image "$SCAN_IMAGE"', docker: sock]
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
              int blocking = securityReport.blocking(report)
              if (blocking < 0) { error("Trivy ${s.name} report has no 'blocking:' line — the template is broken.") }
              if (blocking > 0) { blocked << "${s.name} (${blocking})" }
            }

            if (blocked) {
              error("Fixable ${gate} vulnerabilities in: ${blocked.join(', ')} — marked ✗ in the report above. " +
                    'Upgrade the package or base image, or accept the risk in .trivyignore with a comment saying why.')
            }
          }
        }
        // The readable reports go into security-report.txt; the raw JSON stays.
        post { always { archiveArtifacts artifacts: 'trivy-*.json', allowEmptyArchive: true } }
      }

      // A new image is pushed; an existing one only gains its name for this
      // environment. On main this is where the build ends: prod-vX.Y.Z is in
      // ECR, ready for the release job.
      stage('Publish image') {
        when {
          allOf {
            environment name: 'IS_DEPLOY', value: 'true'
            expression { env.ALREADY_BUILT == 'false' || env.REUSE_FROM }
          }
        }
        steps { script { publishImage(cfg.service) } }
      }

      // ── Deploy ─────────────────────────────────────────────────────────────

      // Skipped for manualDeploy environments (prod, by default).
      stage('Deploy') {
        when { environment name: 'AUTO_DEPLOY', value: 'true' }
        steps {
          script {
            // Only when prod is NOT in manualDeploy: prod then waits here for
            // prodApprovers, and the approver is who the release is recorded
            // against. Inside Deploy, so dev and uat show no skipped stage.
            if (env.DEPLOY_ENV == 'prod') {
              approveProd(message: "Deploy ${cfg.service} ${env.IMAGE_TAG} to PRODUCTION? (${imageOrigin()})",
                          ok: 'Deploy to prod', submitters: approvers,
                          notice: "${cfg.service} ${env.IMAGE_TAG} → prod (${imageOrigin()})", requestedBy: 'pushed')
            }

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
      // First of the post blocks, so it runs on every outcome: one
      // security-report.txt with Gitleaks, SonarQube and both Trivy scans —
      // and which of them never ran, when the build stopped early.
      always {
        script { securityReport.write(gate: gate, imageOrigin: env.IS_DEPLOY == 'true' ? imageOrigin() : null) }
      }
      success {
        script {
          notifyTelegram('SUCCESS', '✅', "${cfg.service} ${env.IMAGE_TAG ?: ''}" +
            (env.AUTO_DEPLOY == 'true' ? " → ${env.DEPLOY_ENV}"
             : env.IS_DEPLOY == 'true' ? " in ECR — release to ${env.DEPLOY_ENV} with the release job (${imageOrigin()})"
             : ' (CI)') + "\nby ${env.INITIATOR ?: 'unknown'}")
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
        // Scoped to this build. A plain `docker image prune` also deletes the
        // untagged stage images (AS build, AS prod-deps) of a build another
        // job is running right now — it then dies on
        //   invalid from flag value build: No such image: sha256:…
        // (auth-api develop #2, while core-api's failed build cleaned up).
        // Only dangling images older than an hour go: every build here is
        // timed out at 45 minutes, so none of them is still being used.
        sh '''
          docker rmi "$IMAGE" ${SCAN_IMAGE:+"$SCAN_IMAGE"} 2>/dev/null || true
          docker image prune -f --filter until=1h >/dev/null 2>&1 || true
          rm -rf node_modules coverage .scannerwork .platform .gitops trivy-*.json trivy-*.txt security-report.txt
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

// Where IMAGE_TAG's image came from — said wherever a person decides on prod.
String imageOrigin() {
  return env.REUSE_FROM ? "same image as ${env.REUSE_FROM}, not rebuilt"
       : env.ALREADY_BUILT == 'true' ? 'already in ECR under this name'
       : 'BUILT FRESH — this image never ran in dev or uat'
}

// Puts IMAGE_TAG in ECR: names the existing image REUSE_FROM, or pushes the
// image this build made. The repository already exists — Terraform's
// (global/); the instance profile may push to upskill-devops/* and create
// nothing.
void publishImage(String service) {
  if (env.REUSE_FROM) {
    imageTag.add(service, env.REUSE_FROM, env.IMAGE_TAG)
    return
  }
  sh """
    ${awsCmd()} ecr get-login-password | docker login --username AWS --password-stdin '${platform.registry()}'
    docker push "\$IMAGE"
    docker logout '${platform.registry()}'
  """
}

// Pulls an image already in ECR, for the image scan of a build that names it
// rather than building it. cleanup removes it again.
void pullImage(String ref) {
  sh """
    ${awsCmd()} ecr get-login-password | docker login --username AWS --password-stdin '${platform.registry()}'
    docker pull '${ref}'
    docker logout '${platform.registry()}'
  """
}

// The aws CLI as a shell command, for use inside a larger `sh` — piping into
// docker login does not fit runTool().
String awsCmd() {
  return "docker run --rm -e AWS_DEFAULT_REGION=${platform.cfg().awsRegion} ${platform.toolImage('awsCli')}"
}
