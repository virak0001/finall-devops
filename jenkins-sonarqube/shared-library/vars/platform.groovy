// Facts about the platform every pipeline shares — the one place they live.
//
//   platform.host('uat')              → uat.devops-selft-learning.xyz
//   platform.image('auth-api', tag)   → <registry>/upskill-devops/auth-api:<tag>
//   platform.cfg().clusterRepo
//
// They mirror ../terraform (region, account, ECR prefix, hostnames) and
// ../cluster (repository, environments). Copied, not discovered, because
// Jenkins has no access to either project's state — when one of them changes,
// change it here too.
//
// Plain methods and plain maps only. A closure kept in a pipeline variable has
// to survive Jenkins serialising the build at every step, and that is a common
// way for a shared library to fail with NotSerializableException.

def cfg() {
  return [
    awsRegion    : 'us-east-1',
    accountId    : '570417737010',
    ecrPrefix    : 'upskill-devops',

    // The GitOps repository. A deploy is a commit to helm/env/<env>.yaml here.
    clusterRepo  : 'github.com/devops-infra-virak-ran/cluster.git',
    clusterBranch: 'main',
    gitopsCredentialsId: 'github-cluster-repo',

    // Each service's repository — the promote job reads release tags from
    // here. Mirrors docker/jenkins/init.groovy.d/40-github.groovy.
    serviceRepos : [
      'auth-api'   : 'github.com/virak-01/aws-auth.git',
      'core-api'   : 'github.com/virak-01/api-ops.git',
      'client-side': 'github.com/virak-01/frontend.git',
    ],
    serviceRepoCredentialsId: 'git-token',

    // dev ← every build of main. uat and prod ← the promote job only.
    environments : ['dev', 'uat', 'prod'],
    hosts        : [
      dev : 'dev.devops-selft-learning.xyz',
      uat : 'uat.devops-selft-learning.xyz',
      prod: 'devops-selft-learning.xyz',
    ],

    // Where every deployment is recorded — terraform/global/deployments.tf.
    deploymentsLogGroup: '/upskill-devops/deployments',

    // Tool images, pinned. `:latest` meant a scanner could change its verdict
    // between two builds of the same commit.
    tools: [
      git     : 'alpine/git:v2.52.0',
      awsCli  : 'amazon/aws-cli:2.27.50',
      trivy   : 'aquasec/trivy:0.75.0',
      gitleaks: 'zricethezav/gitleaks:v8.30.1',
      sonar   : 'sonarsource/sonar-scanner-cli:12.2',
      node    : 'node:22-bookworm',      // full image: python3/make/g++ for native modules
      python  : 'python:3.12-slim',      // bash + python3, for the cluster repo's scripts
      k8s     : 'alpine/k8s:1.36.4',     // curl + jq, for the Argo CD API
    ],
  ]
}

String registry() {
  def c = cfg()
  return "${c.accountId}.dkr.ecr.${c.awsRegion}.amazonaws.com"
}

String repository(String service) {
  return "${cfg().ecrPrefix}/${service}"
}

String image(String service, String tag) {
  return "${registry()}/${repository(service)}:${tag}"
}

String host(String environment) {
  def h = cfg().hosts[environment]
  if (!h) {
    error("platform.host(): no environment '${environment}'")
  }
  return h
}

String argocd(String environment) {
  return "argocd.${host(environment)}"
}

String argocdTokenId(String environment) {
  return "argocd-token-${environment}"
}

String toolImage(String name) {
  def i = cfg().tools[name]
  if (!i) {
    error("platform.toolImage(): no pinned image named '${name}'")
  }
  return i
}
