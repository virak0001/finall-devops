// Promote or roll back a service in uat or prod. The cluster repository's
// Jenkinsfile is the whole configuration:
//
//   @Library('platform') _
//   promotePipeline(
//     services: ['auth-api': [team: 'api-service', smokePaths: ['/api/auth/health']], ...],
//     prodApprovers: 'admin',
//   )
//
// Parameters, chosen when the job is run:
//
//   SERVICE   which service
//   TARGET    uat (from dev) or prod (from uat)
//   ACTION    promote — the image the source environment runs
//             rollback — restore the tag TARGET ran before its current one
//   TAG       optional — promote: this image instead (any of its names);
//             rollback: this exact tag instead of the previous one
//
// promote never builds: the image must already be in ECR, which means it
// already passed every test and scan in servicePipeline. uat gets exactly what
// dev ran, prod exactly what uat accepted — the SAME image, given the target's
// name (vars/imageTag.groovy):
//
//   dev-5a87e72  ──promote to uat──►   uat-5a87e72    (same digest)
//   uat-5a87e72  ──promote to prod──►  prod-v1.0.8    (same digest)
//
// prod's name is the release tag (vX.Y.Z) on the image's commit, read from the
// service repository. A commit without one cannot go to prod: tag it first.
// Pushing that commit to main already puts prod-vX.Y.Z in ECR (servicePipeline
// skips Deploy for prod); this job then deploys it. Otherwise it adds the
// name itself, after the approval.
//
// prod needs an approval from prodApprovers. The approver is recorded as the
// initiator — in the commit trailer, the deployment record and the build. A
// promotion that fails its checks in uat or prod is rolled back by itself.

def call(Map cfg) {
  if (!cfg.services) { error('promotePipeline: services is required') }
  List names = cfg.services.keySet() as List
  String approvers = cfg.prodApprovers ?: 'admin'

  pipeline {
    agent any

    options {
      // One release at a time across every service and environment: two
      // promotions racing to the same env file is the conflict worth avoiding.
      disableConcurrentBuilds()
      buildDiscarder(logRotator(numToKeepStr: '100'))
      timeout(time: 90, unit: 'MINUTES')
      timestamps()
    }

    parameters {
      choice(name: 'SERVICE', choices: names, description: 'Service to release')
      choice(name: 'TARGET', choices: ['uat', 'prod'], description: 'uat takes what dev runs; prod takes what uat runs (or TAG=prod-vX.Y.Z from a main build)')
      choice(name: 'ACTION', choices: ['promote', 'rollback'], description: 'rollback restores the previous tag in TARGET')
      string(name: 'TAG', defaultValue: '', description: 'Optional. promote: this image instead of what the source runs (e.g. dev-5a87e72). rollback: this exact tag.')
    }

    stages {
      stage('Resolve') {
        steps {
          script {
            def svc = cfg.services[params.SERVICE]
            env.TEAM = svc.team
            env.SOURCE_ENV = params.TARGET == 'prod' ? 'uat' : 'dev'
            env.INITIATOR = initiator()

            env.CURRENT_TAG = gitops.getTag(params.TARGET, params.SERVICE)
            env.FROM_TAG = ''
            if (params.ACTION == 'rollback') {
              env.RELEASE_TAG = params.TAG?.trim() ?: gitops.previousTag(params.TARGET, params.SERVICE)
            } else {
              env.SOURCE_TAG = params.TAG?.trim() ?: gitops.getTag(env.SOURCE_ENV, params.SERVICE)
              env.RELEASE_TAG = targetName(params.TARGET, params.SERVICE, env.SOURCE_TAG)
            }

            currentBuild.displayName = "#${env.BUILD_NUMBER} ${params.ACTION} ${params.SERVICE} → ${params.TARGET}"
            currentBuild.description = "${env.CURRENT_TAG} → ${env.RELEASE_TAG}"

            if (env.RELEASE_TAG == env.CURRENT_TAG) {
              env.NOTHING_TO_DO = 'true'
              echo "${params.SERVICE} already runs ${env.RELEASE_TAG} in ${params.TARGET} — nothing to do."
              return
            }
            env.NOTHING_TO_DO = 'false'

            // Built and scanned by servicePipeline, or it does not ship.
            def named = imageTag.find(params.SERVICE, env.RELEASE_TAG)
            if (named) {
              // A promotion whose name exists must be the same commit's image.
              String sha = env.SOURCE_TAG ? imageTag.shaOf(env.SOURCE_TAG) : null
              String other = sha ? imageTag.otherCommit(named, sha) : null
              if (other) {
                error("${env.RELEASE_TAG} is already the image of commit ${other}, not ${sha}. " +
                      'A release names one image forever — tag the commit with a new version.')
              }
            } else if (params.ACTION == 'promote' && env.SOURCE_TAG != env.RELEASE_TAG
                       && imageTag.find(params.SERVICE, env.SOURCE_TAG)) {
              env.FROM_TAG = env.SOURCE_TAG
            } else {
              error("${platform.repository(params.SERVICE)}:${env.SOURCE_TAG ?: env.RELEASE_TAG} is not in ECR. " +
                    'Only images built by the service pipeline can be promoted.')
            }

            echo """
              ${params.ACTION} ${params.SERVICE} in ${params.TARGET}
                now      : ${env.CURRENT_TAG}
                becomes  : ${env.RELEASE_TAG}${env.FROM_TAG ? " — the image ${env.FROM_TAG}${params.TAG?.trim() ? '' : " (what ${env.SOURCE_ENV} runs)"}, given this name" : ''}
                image    : ${platform.image(params.SERVICE, env.RELEASE_TAG)}
                asked by : ${env.INITIATOR}
            """.stripIndent()
          }
        }
      }

      stage('Deploy') {
        when { environment name: 'NOTHING_TO_DO', value: 'false' }
        steps {
          script {
            // prod waits here for prodApprovers — inside Deploy, so dev and
            // uat releases show no skipped approval stage.
            if (params.TARGET == 'prod') {
              approveProd(message: "${params.ACTION} ${params.SERVICE} in PRODUCTION: ${env.CURRENT_TAG} → ${env.RELEASE_TAG}?",
                          ok: 'Release to prod', submitters: approvers,
                          notice: "${params.ACTION} ${params.SERVICE} in prod: ${env.CURRENT_TAG} → ${env.RELEASE_TAG}",
                          requestedBy: 'asked')
            }

            // After the approval: a turned-down release leaves no name behind.
            if (env.FROM_TAG) {
              imageTag.add(params.SERVICE, env.FROM_TAG, env.RELEASE_TAG)
            }

            def svc = cfg.services[params.SERVICE]
            deploy(environment: params.TARGET, service: params.SERVICE, team: svc.team,
                   tag: env.RELEASE_TAG, smokePaths: svc.smokePaths ?: [],
                   initiator: env.INITIATOR, action: params.ACTION,
                   source: "${env.SOURCE_ENV}:${env.SOURCE_TAG ?: env.RELEASE_TAG}",
                   // A rollback that fails has nothing safer to fall back to.
                   rollbackOnFailure: params.ACTION == 'promote',
                   reason: params.ACTION == 'rollback'
                     ? "Rollback of ${params.SERVICE} in ${params.TARGET}: ${env.CURRENT_TAG} → ${env.RELEASE_TAG}"
                     : "Promotion of ${params.SERVICE} from ${env.SOURCE_ENV} to ${params.TARGET}")
          }
        }
      }
    }

    post {
      success {
        script {
          if (env.NOTHING_TO_DO != 'true') {
            notifyTelegram('RELEASED', '🚀',
              "${params.SERVICE} ${env.RELEASE_TAG} → ${params.TARGET}\nby ${env.INITIATOR}")
          }
        }
      }
      failure {
        script {
          notifyTelegram('FAILED', '❌',
            "${params.ACTION} ${params.SERVICE} → ${params.TARGET} (${env.RELEASE_TAG ?: '?'})\nby ${env.INITIATOR ?: 'unknown'}")
        }
      }
      // cleanup, not always: Jenkins runs `always` FIRST, before failure{},
      // which then could not see .platform/deployment.json and wrote a
      // second, wrong BUILD_FAILED record. cleanup runs last.
      cleanup {
        sh 'rm -rf .platform .gitops'
      }
    }
  }
}

// The name the image `source` gets in `target`:
//   dev-5a87e72 → uat-5a87e72                 the same commit, uat's name
//   uat-5a87e72 → prod-v1.0.8                 the commit's release tag
//   a name already the target's → unchanged   (TAG=prod-v1.0.7 to re-release)
String targetName(String target, String service, String source) {
  if (source.startsWith("${target}-")) {
    return source
  }
  String sha = imageTag.shaOf(source)
  if (!sha) {
    error("Cannot tell which commit ${source} was built from, so it cannot be named for ${target}. " +
          'Build that commit again from develop, or set TAG to a dev-/uat- tag.')
  }
  if (target == 'uat') {
    return imageTag.forEnv('uat', sha, null)
  }
  String version = imageTag.releaseVersion(service, sha)
  if (!version) {
    error("${service} commit ${sha} has no release tag, and prod images are named after one. " +
          "Tag it, then run this again:\n    git tag v1.2.3 ${sha} && git push origin v1.2.3")
  }
  return imageTag.forEnv('prod', sha, version)
}
