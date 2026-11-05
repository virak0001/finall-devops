# Pipelines — how a commit reaches production

Every service runs the same pipeline from the shared library in
`shared-library/`, so each repository's Jenkinsfile is five lines.

```
git push (any branch / PR)
   │  GitHub webhook → http://<jenkins>:8080/github-webhook/   (signed, SG-limited)
   ▼
multibranch job auth-api / core-api / client-side
   Prepare        version tag = git describe (3.0.6-2-g73bf736), who started it
   Secret scan    Gitleaks                                   ── fails the build
   Unit tests     npm ci + test:cov                          ── fails the build
   SonarQube      analysis + quality gate                    ── fails the build
   Build          docker build, labels: revision, version, built-by, build-url
   Security scan  Trivy fs + image — fixable CRITICAL        ── fails the build
                  report CRITICAL → LOW, ✗ = blocks; archived trivy-*.txt/.json
   ── develop / testing / main only ──────────────────────────────────────────
   Push           ECR, immutable tag (skipped if this commit is already there)
   Approve prod   main only — prodApprovers
   Deploy         commit tag → Argo CD Synced+Healthy → image check → smoke test
                  develop → dev · testing → uat (auto-rollback) · main → prod (auto-rollback)

release job (Build with Parameters: SERVICE, TARGET, ACTION)
   promote or roll back one service by hand, outside a merge
```

The image tag is the commit (`git describe`). A fast-forward merge
develop → testing → main moves the same commit, so uat and prod reuse the
image dev ran — not rebuilt. A merge commit is a new commit and a new image.

## Who did what

| Where | What it holds |
| --- | --- |
| Image labels | `docker inspect <image>` → revision, version, built-by, build-url |
| Cluster repo commits | trailers: `Environment`, `Service`, `Image`, `Initiated-By`, `Source-Commit`, `Jenkins-Build` |
| CloudWatch Logs `/upskill-devops/deployments` | one JSON event per deploy, promotion, rollback, failed build — with `status` |
| Alarm `upskill-devops-deployment-failed` | any FAILED / ROLLED_BACK / ROLLBACK_FAILED / BUILD_FAILED, to SNS |
| Telegram | every build result, approvals waiting, releases |

```bash
# who released what to prod
git -C ../cluster log --format='%h %ad %(trailers:key=Initiated-By,valueonly,separator=) %s' --date=short -- helm/env/prod.yaml
```

## One-time setup

1. **Tokens in `docker/.env`** (see `docker/.env.example`):
   `GIT_TOKEN` (read the service repos), `GITOPS_TOKEN` (write the cluster
   repo only), `GITHUB_WEBHOOK_SECRET` (`openssl rand -hex 32`), the SonarQube
   tokens, Telegram.
2. **Argo CD tokens**, once each environment's cluster is up:
   `make -C ../cluster argocd-ci-token WORKSPACE=dev` → `ARGOCD_TOKEN_DEV=…`.
   Add this Jenkins's Elastic IP to `ADMIN_ALLOWED_CIDRS` in
   `../cluster/platform/<ws>.local.env` and `make argocd-expose` — Jenkins
   talks to Argo CD through the ALB.
3. **`make apply && make deploy`** — the security group opens 8080 to GitHub's
   webhook ranges; Jenkins rebuilds with `docker/jenkins/plugins.txt`, and the
   init scripts create the credentials, the `platform` library and the jobs
   (`auth-api`, `core-api`, `client-side`, `release`).
4. **`gh auth login && make webhooks`** — a webhook on each service repo.
5. **Run `release` once** with no parameters — it fails, and registers them.

## Gotchas

- **`git describe` needs tags** in the checkout; the jobs fetch them. A repo
  with no `v*.*.*` tag versions from `0.0.0-<n>-g<sha>`.
- **A gate that fails on old CVEs** — accept a specific one with a line in
  `.trivyignore` (the CVE id and a comment why), never by lowering the gate.
- **The shared library is trusted code**: anyone who can push to this repo's
  `master` changes every pipeline. Protect the branch.
- **Testing a library change**: `@Library('platform@my-branch') _` in one
  service's Jenkinsfile, on a branch.
