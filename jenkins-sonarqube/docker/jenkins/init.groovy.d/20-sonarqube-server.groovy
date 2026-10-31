/*
 * Registers the SonarQube server in Jenkins global config (Manage Jenkins >
 * System > SonarQube servers) — separate from the credential
 * 10-credentials.groovy creates. withSonarQubeEnv('SonarQube') needs both: a
 * credential to authenticate with, AND an installation entry saying where the
 * server is and which credential to use. Without this, every pipeline that
 * calls withSonarQubeEnv fails immediately with "does not match any
 * configured installation. Number of installations that can be configured: 0."
 *
 * Runs on every start, so it must be idempotent like 10-credentials.groovy:
 * replace the installation by name if it exists, add it if not.
 *
 * Also drops any installation with a blank name — one was found already
 * sitting in this Jenkins's config (created by hand at some point, not by
 * this script), and a blank-named entry can never be the target of
 * withSonarQubeEnv('SonarQube') anyway since jobs always ask for a specific
 * name. Worth clearing out even though it turned out not to be the cause of
 * the bug below.
 *
 * IMPORTANT: this sets the token as an explicit hudson.util.Secret
 * (serverAuthenticationToken), not just credentialsId. Constructing the
 * installation with only credentialsId set (the 7-arg constructor) reliably
 * reproduced a bug on this plugin version (sonar@2.19.0): after conf.save(),
 * the persisted XML had credentialsId silently dropped and replaced by a
 * serverAuthenticationToken this script never set — and whatever that
 * resolved to made waitForQualityGate fail every run with 401 on
 * /api/ce/task, even though the sonar-token credential itself is valid
 * (confirmed by curling the same endpoint with it directly). Setting the
 * Secret explicitly, from the same env var 10-credentials.groovy uses for
 * the credential, sidesteps whatever that resolution path is doing wrong.
 */

import hudson.plugins.sonar.SonarGlobalConfiguration
import hudson.plugins.sonar.SonarInstallation
import hudson.plugins.sonar.model.TriggersConfig
import hudson.util.Secret

def env = System.getenv()

def name = env['SONARQUBE_INSTALLATION_NAME'] ?: 'SonarQube'
// The Docker Compose service name — Jenkins and SonarQube share the compose
// network, so this resolves container-to-container without going out over
// the public IP and through the security group at all.
def serverUrl = env['SONARQUBE_SERVER_URL'] ?: 'http://sonarqube:9000'
def credentialsId = env['SONAR_CREDENTIALS_ID'] ?: 'sonar-token'
def rawToken = env['SONAR_TOKEN']

def conf = SonarGlobalConfiguration.get()
def installations = conf.getInstallations().findAll { it.getName() && it.getName() != name }

installations << new SonarInstallation(
    name,
    serverUrl,
    credentialsId,
    rawToken ? Secret.fromString(rawToken) : null,
    '',   // mojoVersion — deprecated, unused
    '',   // additionalProperties
    '',   // additionalAnalysisProperties
    '',   // webhookSecretId — not used; waitForQualityGate polls instead
    new TriggersConfig()
)

conf.setInstallations(installations as SonarInstallation[])
conf.save()

println "--- init.groovy.d/20-sonarqube-server ---"
println "  set  ${name}  ->  ${serverUrl}  (token set: ${rawToken ? 'yes' : 'NO - SONAR_TOKEN unset'})"
