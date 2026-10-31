/*
 * Credentials, from the environment.
 *
 * Runs on every Jenkins start, so it must be idempotent: each entry is an
 * upsert, not an add. Adding twice throws, and a throwing init script leaves
 * Jenkins up but half-configured — with the failure only in the container log.
 *
 * Values come from the container environment, which docker-compose fills from
 * docker/.env. Nothing secret is in git, and nothing secret is printed here:
 * only the id and whether it was created or updated.
 *
 * An unset variable is skipped rather than stored empty. A credential holding
 * an empty token fails at `git fetch` with a 403 that looks like a permissions
 * problem on the remote.
 */

import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import hudson.util.Secret
import jenkins.model.Jenkins
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl

def env = System.getenv()
def store = SystemCredentialsProvider.getInstance().getStore()
def domain = Domain.global()

// Replace by id if it is already there, otherwise add. Returns what it did so
// the log reads as a summary rather than a stack trace.
def upsert = { credential ->
    def existing = store.getCredentials(domain).find { it.id == credential.id }
    if (existing) {
        store.updateCredentials(domain, existing, credential)
        return "updated"
    }
    store.addCredentials(domain, credential)
    return "created"
}

def report = []

// ─── Git ─────────────────────────────────────────────────────────────────────
// A personal access token goes in the PASSWORD field, not a token field —
// GitHub, GitLab and Bitbucket all accept a PAT over HTTPS basic auth. The
// username is mostly ignored by GitHub but must not be blank.
if (env['GIT_TOKEN']) {
    def id = env['GIT_CREDENTIALS_ID'] ?: 'git-token'
    def what = upsert(new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL,
        id,
        'Git over HTTPS — personal access token (managed by init.groovy.d)',
        env['GIT_USERNAME'] ?: 'git',
        env['GIT_TOKEN']
    ))
    report << "  ${what}  ${id}  (username/password)"
} else {
    report << "  skipped  git-token  — GIT_TOKEN is not set"
}

// ─── SonarQube ───────────────────────────────────────────────────────────────
// Secret text, because the SonarQube Scanner step wants a bare token. Use a
// USER token, not a project-analysis token: a project token analyses fine but
// silently fails the quality-gate webhook callback.
if (env['SONAR_TOKEN']) {
    def id = env['SONAR_CREDENTIALS_ID'] ?: 'sonar-token'
    def what = upsert(new StringCredentialsImpl(
        CredentialsScope.GLOBAL,
        id,
        'SonarQube user token (managed by init.groovy.d)',
        Secret.fromString(env['SONAR_TOKEN'])
    ))
    report << "  ${what}  ${id}  (secret text)"
} else {
    report << "  skipped  sonar-token  — SONAR_TOKEN is not set"
}

// ─── SonarQube (employee-service) ────────────────────────────────────────────
// Separate per-project token — see the comment on SONAR_TOKEN above about
// project-analysis vs. user tokens.
if (env['SONAR_EMPLOYEE_SERVICE_TOKEN']) {
    def id = env['SONAR_EMPLOYEE_SERVICE_CREDENTIALS_ID'] ?: 'sonar-employee-service-token'
    def what = upsert(new StringCredentialsImpl(
        CredentialsScope.GLOBAL,
        id,
        'SonarQube token — employee-service (managed by init.groovy.d)',
        Secret.fromString(env['SONAR_EMPLOYEE_SERVICE_TOKEN'])
    ))
    report << "  ${what}  ${id}  (secret text)"
} else {
    report << "  skipped  sonar-employee-service-token  — SONAR_EMPLOYEE_SERVICE_TOKEN is not set"
}

// ─── SonarQube (auth-service) ────────────────────────────────────────────────
// Per-project token for the auth-service pipeline — same shape as the
// employee-service one above.
if (env['SONAR_AUTH_SERVICE_TOKEN']) {
    def id = env['SONAR_AUTH_SERVICE_CREDENTIALS_ID'] ?: 'sonar-auth-service-token'
    def what = upsert(new StringCredentialsImpl(
        CredentialsScope.GLOBAL,
        id,
        'SonarQube token — auth-service (managed by init.groovy.d)',
        Secret.fromString(env['SONAR_AUTH_SERVICE_TOKEN'])
    ))
    report << "  ${what}  ${id}  (secret text)"
} else {
    report << "  skipped  sonar-auth-service-token  — SONAR_AUTH_SERVICE_TOKEN is not set"
}

// ─── SonarQube (core-service) ────────────────────────────────────────────────
// Per-project token for the core-service pipeline — same shape as the
// auth-service one above.
if (env['SONAR_CORE_SERVICE_TOKEN']) {
    def id = env['SONAR_CORE_SERVICE_CREDENTIALS_ID'] ?: 'sonar-core-service-token'
    def what = upsert(new StringCredentialsImpl(
        CredentialsScope.GLOBAL,
        id,
        'SonarQube token — core-service (managed by init.groovy.d)',
        Secret.fromString(env['SONAR_CORE_SERVICE_TOKEN'])
    ))
    report << "  ${what}  ${id}  (secret text)"
} else {
    report << "  skipped  sonar-core-service-token  — SONAR_CORE_SERVICE_TOKEN is not set"
}

// ─── Telegram ──────────────────────────────────────────────────────────────
// frontend/Jenkinsfile's notifyTelegram() wants a usernamePassword credential
// — username=chat_id, password=bot token — rather than a dedicated token
// type, so no extra plugin is needed beyond what Jenkins core ships.
if (env['TELEGRAM_BOT_TOKEN']) {
    def id = env['TELEGRAM_CREDENTIALS_ID'] ?: 'telegram-notify'
    def what = upsert(new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL,
        id,
        'Telegram bot — build notifications (managed by init.groovy.d)',
        env['TELEGRAM_CHAT_ID'] ?: '',
        env['TELEGRAM_BOT_TOKEN']
    ))
    report << "  ${what}  ${id}  (username/password)"
} else {
    report << "  skipped  telegram-notify  — TELEGRAM_BOT_TOKEN is not set"
}

// ─── GitOps repository ───────────────────────────────────────────────────────
// The token the pipelines push image tags to the cluster repo with. Separate
// from git-token, which only has to READ the service repos: this one can
// change what runs in every environment, so it is scoped to that one repo.
if (env['GITOPS_TOKEN']) {
    def what = upsert(new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL,
        'github-cluster-repo',
        'GitOps — write to the cluster repo (managed by init.groovy.d)',
        env['GITOPS_USERNAME'] ?: 'git',
        env['GITOPS_TOKEN']
    ))
    report << "  ${what}  github-cluster-repo  (username/password)"
} else {
    report << "  skipped  github-cluster-repo  — GITOPS_TOKEN is not set"
}

// ─── Argo CD, one per environment ────────────────────────────────────────────
// Tokens of the `ci` account (cluster/controllers/argocd.yaml): read
// applications, sync them. `make argocd-ci-token WORKSPACE=<env>` in the
// cluster project prints one.
['dev', 'uat', 'prod'].each { e ->
    def value = env["ARGOCD_TOKEN_${e.toUpperCase()}"]
    def id = "argocd-token-${e}"
    if (value) {
        def what = upsert(new StringCredentialsImpl(
            CredentialsScope.GLOBAL, id,
            "Argo CD ci account — ${e} (managed by init.groovy.d)",
            Secret.fromString(value)))
        report << "  ${what}  ${id}  (secret text)"
    } else {
        report << "  skipped  ${id}  — ARGOCD_TOKEN_${e.toUpperCase()} is not set"
    }
}

// ─── GitHub webhook secret ───────────────────────────────────────────────────
// Jenkins checks every webhook delivery's signature against this, so a POST
// to /github-webhook/ from anyone but GitHub starts nothing.
// init.groovy.d/40-github.groovy points the GitHub plugin at it.
if (env['GITHUB_WEBHOOK_SECRET']) {
    def what = upsert(new StringCredentialsImpl(
        CredentialsScope.GLOBAL, 'github-webhook-secret',
        'GitHub webhook shared secret (managed by init.groovy.d)',
        Secret.fromString(env['GITHUB_WEBHOOK_SECRET'])))
    report << "  ${what}  github-webhook-secret  (secret text)"
} else {
    report << "  skipped  github-webhook-secret  — GITHUB_WEBHOOK_SECRET is not set"
}

Jenkins.instance.save()
println "--- init.groovy.d/10-credentials ---"
report.each { println it }
