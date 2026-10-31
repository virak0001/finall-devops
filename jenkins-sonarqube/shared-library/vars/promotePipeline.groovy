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
//   ACTION    promote — copy the tag the source environment runs
//             rollback — restore the tag TARGET ran before its current one
//   TAG       optional: a specific tag instead of the above
//
// promote never builds: the tag must already be in ECR, which means it already
// passed every test and scan in servicePipeline. uat gets exactly what dev
// ran, prod exactly what uat accepted.
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
      choice(name: 'TARGET', choices: ['uat', 'prod'], description: 'uat takes what dev runs; prod takes what uat runs')
      choice(name: 'ACTION', choices: ['promote', 'rollback'], description: 'rollback restores the previous tag in TARGET')
      string(name: 'TAG', defaultValue: '', description: 'Optional: deploy this exact tag instead')
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
            if (params.TAG?.trim()) {
              env.RELEASE_TAG = params.TAG.trim()
            } else if (params.ACTION == 'rollback') {
              env.RELEASE_TAG = gitops.previousTag(params.TARGET, params.SERVICE)
            } else {
              env.RELEASE_TAG = gitops.getTag(env.SOURCE_ENV, params.SERVICE)
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
            int found = runTool('awsCli',
              "ecr describe-images --repository-name '${platform.repository(params.SERVICE)}' --image-ids imageTag='${env.RELEASE_TAG}'",
              returnStatus: true)
            if (found != 0) {
              error("${platform.repository(params.SERVICE)}:${env.RELEASE_TAG} is not in ECR. " +
                    'Only images built by the service pipeline can be promoted.')
            }

            echo """
              ${params.ACTION} ${params.SERVICE} in ${params.TARGET}
                now      : ${env.CURRENT_TAG}
                becomes  : ${env.RELEASE_TAG}${params.ACTION == 'promote' && !params.TAG?.trim() ? " (what ${env.SOURCE_ENV} runs)" : ''}
                image    : ${platform.image(params.SERVICE, env.RELEASE_TAG)}
                asked by : ${env.INITIATOR}
            """.stripIndent()
          }
        }
      }

      stage('Approve') {
        when {
          allOf {
            expression { params.TARGET == 'prod' }
            environment name: 'NOTHING_TO_DO', value: 'false'
          }
        }
        steps {
          script {
            notifyTelegram('WAITING FOR APPROVAL', '⏳',
              "${params.ACTION} ${params.SERVICE} in prod: ${env.CURRENT_TAG} → ${env.RELEASE_TAG}\nasked by ${env.INITIATOR}")
            timeout(time: 60, unit: 'MINUTES') {
              // submitterParameter: the approver's user id comes back, and is
              // who the release is recorded against.
              env.APPROVER = input(
                message: "${params.ACTION} ${params.SERVICE} in PRODUCTION: ${env.CURRENT_TAG} → ${env.RELEASE_TAG}?",
                ok: 'Release to prod',
                submitter: approvers,
                submitterParameter: 'APPROVER')
            }
            env.DEPLOY_AUTHOR = "${env.APPROVER} <${env.APPROVER}@jenkins.local>"
            env.INITIATOR = "${env.APPROVER} (approved; asked by ${env.INITIATOR})"
          }
        }
      }

      stage('Deploy') {
        when { environment name: 'NOTHING_TO_DO', value: 'false' }
        steps {
          script {
            def svc = cfg.services[params.SERVICE]
            deploy(environment: params.TARGET, service: params.SERVICE, team: svc.team,
                   tag: env.RELEASE_TAG, smokePaths: svc.smokePaths ?: [],
                   initiator: env.INITIATOR, action: params.ACTION,
                   source: "${env.SOURCE_ENV}:${env.RELEASE_TAG}",
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
