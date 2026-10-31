/*
 * GitHub → Jenkins: the webhook secret, and the jobs the webhooks trigger.
 *
 *   push / pull request on GitHub
 *        │  POST http://<jenkins>:8080/github-webhook/   (signed with the secret)
 *        ▼
 *   multibranch job for that repo — a build for the branch or PR that changed
 *        │  its Jenkinsfile: servicePipeline (shared library)
 *        ▼
 *   scans and tests on every branch; on main, also build → ECR → dev
 *
 * Creates, if missing, and otherwise updates in place:
 *
 *   auth-api, core-api, client-side   multibranch, one per service repository
 *   release                           the promote/rollback job (cluster repo)
 *
 * Builds, history and anything set by hand in a job's other settings survive a
 * restart: an existing job only has its branch source and triggers replaced.
 *
 * The GitHub side — a webhook on each repository — is scripts/github-webhooks.sh.
 *
 * Each step is guarded, so a missing plugin reports itself here and leaves the
 * rest of Jenkins working, rather than stopping startup.
 */

import com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger
import hudson.plugins.git.BranchSpec
import hudson.plugins.git.GitSCM
import hudson.plugins.git.extensions.impl.CloneOption
import jenkins.branch.BranchSource
import jenkins.model.Jenkins
import jenkins.plugins.git.traits.CloneOptionTrait
import org.jenkinsci.plugins.github.GitHubPlugin
import org.jenkinsci.plugins.github.config.HookSecretConfig
import org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait
import org.jenkinsci.plugins.github_branch_source.GitHubSCMSource
import org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject

def env = System.getenv()
def jenkins = Jenkins.get()
def credentialsId = env['GIT_CREDENTIALS_ID'] ?: 'git-token'
def report = []

// The service repositories, one multibranch job each. Mirrors the catalogue in
// the cluster repo (helm/values/<team>/services.yaml) — a new service is a new
// line here, a restart, and scripts/github-webhooks.sh.
def services = [
    'auth-api'   : [owner: 'virak-01',  repo: 'aws-auth'],
    'core-api'   : [owner: 'virak-01',  repo: 'api-ops'],
    'client-side': [owner: 'virak-01',  repo: 'frontend'],
]
def clusterRepo = env['CLUSTER_REPO_URL'] ?: 'https://github.com/devops-infra-virak-ran/cluster.git'

// ─── Webhook signature ───────────────────────────────────────────────────────
// SHA-256 (X-Hub-Signature-256). A delivery whose signature does not match
// the secret is rejected before it can trigger anything.
try {
    if (env['GITHUB_WEBHOOK_SECRET']) {
        GitHubPlugin.configuration().setHookSecretConfigs([new HookSecretConfig('github-webhook-secret', 'SHA256')])
        GitHubPlugin.configuration().save()
        report << "  set      webhook secret  (github-webhook-secret, SHA-256)"
    } else {
        report << "  skipped  webhook secret  — GITHUB_WEBHOOK_SECRET is not set; deliveries are NOT verified"
    }
} catch (Throwable t) {
    report << "  FAILED   webhook secret  — ${t}"
}

// ─── One multibranch job per service ─────────────────────────────────────────
services.each { name, gh ->
    try {
        def job = jenkins.getItem(name)
        def created = false
        if (job == null) {
            job = jenkins.createProject(WorkflowMultiBranchProject, name)
            created = true
        } else if (!(job instanceof WorkflowMultiBranchProject)) {
            report << "  skipped  ${name}  — a job of another kind already has this name"
            return
        }

        def source = new GitHubSCMSource(gh.owner, gh.repo)
        source.setCredentialsId(credentialsId)
        source.setTraits([
            // 1: branches that are not also open as a PR (the PR builds them)
            new BranchDiscoveryTrait(1),
            // 1: PRs from this repo, built as merged with their target
            new OriginPullRequestDiscoveryTrait(1),
            // Fetch tags: the image tag is `git describe`, which needs them.
            new CloneOptionTrait(new CloneOption(false, false, null, 10)),
        ])

        // Stable id: Jenkins keys branch history by it, so a restart that
        // replaced the source with a new random id would forget every build.
        source.setId("${name}-github")
        job.getSourcesList().clear()
        job.getSourcesList().add(new BranchSource(source))
        job.setDisplayName(name)
        job.setDescription("${gh.owner}/${gh.repo} — servicePipeline. Managed by init.groovy.d/40-github.groovy.")

        // The webhook is the trigger. This rescan is only the safety net for
        // a delivery that was missed (Jenkins stopped, GitHub retried out).
        job.getTriggers().clear()
        job.addTrigger(new PeriodicFolderTrigger('1h'))
        job.save()

        // A new job scans its repository once now, so branches appear before
        // the first push.
        if (created) {
            job.scheduleBuild()
        }
        report << "  ${created ? 'created' : 'updated'}  ${name}  ←  github.com/${gh.owner}/${gh.repo}"
    } catch (Throwable t) {
        report << "  FAILED   ${name}  — ${t}"
    }
}

// ─── The release job ─────────────────────────────────────────────────────────
// A plain pipeline from the cluster repo's Jenkinsfile (promotePipeline). Run
// by hand — Build with Parameters — never by a push: a release is a decision.
try {
    def job = jenkins.getItem('release')
    def created = false
    if (job == null) {
        job = jenkins.createProject(WorkflowJob, 'release')
        created = true
    }
    def scm = new GitSCM(GitSCM.createRepoList(clusterRepo, credentialsId),
                         [new BranchSpec('*/main')], null, null, [])
    def definition = new CpsScmFlowDefinition(scm, 'Jenkinsfile')
    // Read only the Jenkinsfile, not a full checkout, to start the build.
    definition.setLightweight(true)
    job.setDefinition(definition)
    job.setDescription('Promote a service dev → uat → prod, or roll one back. ' +
                       'The first run only registers the parameters; run it again with them. ' +
                       'Managed by init.groovy.d/40-github.groovy.')
    job.save()
    report << "  ${created ? 'created' : 'updated'}  release  ←  ${clusterRepo} (Jenkinsfile)"
} catch (Throwable t) {
    report << "  FAILED   release  — ${t}"
}

println "--- init.groovy.d/40-github ---"
report.each { println it }
