/*
 * Registers the platform shared library as a global, trusted library named
 * `platform` — what every Jenkinsfile's `@Library('platform') _` loads.
 *
 * It lives in this repository, under shared-library/ (vars/ and resources/),
 * and is fetched fresh from git for each build: a change to it reaches every
 * pipeline on its next run, with nothing to redeploy here.
 *
 * Trusted, because it is global: it runs outside the Groovy sandbox, so it can
 * use JsonOutput and @NonCPS helpers without per-method script approvals. Only
 * people who can push to this repository can change it — treat that branch
 * like production code.
 *
 * Idempotent like the other init scripts: replaces the `platform` entry, keeps
 * any other library.
 */

import jenkins.model.Jenkins
import jenkins.plugins.git.GitSCMSource
import org.jenkinsci.plugins.workflow.libs.GlobalLibraries
import org.jenkinsci.plugins.workflow.libs.LibraryConfiguration
import org.jenkinsci.plugins.workflow.libs.SCMSourceRetriever

def env = System.getenv()
def repo = env['PLATFORM_LIBRARY_REPO'] ?: 'https://github.com/devops-infra-virak-ran/jenkins-sonarqube.git'
def branch = env['PLATFORM_LIBRARY_BRANCH'] ?: 'master'

def source = new GitSCMSource(repo)
// Read access. Public repositories need none, and git-token is skipped
// cleanly by 10-credentials when unset.
source.setCredentialsId(env['GIT_CREDENTIALS_ID'] ?: 'git-token')

def retriever = new SCMSourceRetriever(source)
// vars/ and resources/ are under shared-library/, not at the repo root.
retriever.setLibraryPath('shared-library/')

def library = new LibraryConfiguration('platform', retriever)
library.setDefaultVersion(branch)
library.setImplicit(false)              // only Jenkinsfiles that ask for it
library.setAllowVersionOverride(true)   // @Library('platform@my-branch') to test a change
library.setIncludeInChangesets(false)   // library commits are not the service's changes

def globals = GlobalLibraries.get()
def others = globals.getLibraries().findAll { it.name != 'platform' }
globals.setLibraries(others + [library])
globals.save()

println "--- init.groovy.d/30-shared-library ---"
println "  set  platform  ->  ${repo} @ ${branch} (shared-library/)"
