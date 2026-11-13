# Pipelines — how a commit reaches production

Every service runs the same pipeline from the shared library in
`shared-library/`, so each repository's Jenkinsfile is five lines.

```
git push (any branch / PR)
   │  GitHub webhook → http://<jenkins>:8080/github-webhook/   (signed, SG-limited)
   ▼
multibranch job auth-api / core-api / client-side
   Prepare        image name per environment (below), version = git describe, who started it
                  main: the commit must carry a vX.Y.Z tag     ── fails the build
   Secret scan    Gitleaks                                   ── fails the build
   Unit tests     npm ci + test:cov                          ── fails the build
   SonarQube      analysis + quality gate                    ── fails the build
   Build          docker build, labels: revision, version, built-by, build-url
   Security scan  Trivy fs + image — fixable CRITICAL        ── fails the build
   (every build)  security-report.txt in the build artifacts — Gitleaks, SonarQube
                  (gate, issues, hotspots) and both Trivy scans in one report;
                  a check the build never reached says "not run"
   ── develop / testing / main only ──────────────────────────────────────────
   Publish        new image → push · same commit's image already in ECR → add a name, no rebuild
   Deploy         develop and testing only — main stops after Publish
                  commit tag → Argo CD Synced+Healthy → image check → smoke test
                  develop → dev · testing → uat (auto-rollback)

release job (Build with Parameters: SERVICE, TARGET=prod) — the ONLY way into prod
   approval by prodApprovers → commit tag → Argo CD sync → checks → auto-rollback

release job (Build with Parameters: SERVICE, TARGET, ACTION)
   promote or roll back one service by hand, outside a merge
```

## Image names

One image per commit, built once. Each environment it reaches adds a name —
the image is never rebuilt for one (`shared-library/vars/imageTag.groovy`):

| Branch → env | Name | How |
| --- | --- | --- |
| develop → dev | `dev-5a87e72` | built and pushed (the commit, 7 characters) |
| testing → uat | `uat-5a87e72` | the same image, name added |
| main → prod | `prod-v1.0.8` | the same image, named after the commit's git tag — **pushed only, not deployed** |

**prod is manual.** A main build ends with `prod-v1.0.8` in ECR. Release it
with the `release` job: `SERVICE`, `TARGET=prod`, `ACTION=promote` (takes what
uat runs) or `TAG=prod-v1.0.8` — then approve. `manualDeploy: []` in a
Jenkinsfile would make main deploy by itself, after an approval.

All names of one image share one digest. A fast-forward merge
develop → testing → main moves the same commit, so uat and prod reuse the
image dev ran. A merge commit is a new commit: it is built fresh, and prod's
approval prompt says so. The `release` job adds names the same way.

```bash
# which image does uat run, and what else is it called?
aws ecr describe-images --repository-name upskill-devops/client-side \
  --query 'imageDetails[?imageTags && contains(join(`,`, imageTags), `uat-`)].[imagePushedAt, join(`, `, imageTags)]' \
  --output table
```

`imagePushedAt` is the first push, not when a name was added — for what an
environment runs *now*, read `helm/env/<env>.yaml` in the cluster repo.

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

- **prod needs a release tag.** main fails in Prepare until the commit has
  one: `git tag v1.2.3 <sha> && git push origin v1.2.3`, then Build Now on
  main. A tag cannot be re-released on another commit — use a new version.
- **`git describe` needs tags** in the checkout; the jobs fetch them. A repo
  with no `v*.*.*` tag versions from `0.0.0-<n>-g<sha>`.
- **A gate that fails on old CVEs** — accept a specific one with a line in
  `.trivyignore` (the CVE id and a comment why), never by lowering the gate.
- **The shared library is trusted code**: anyone who can push to this repo's
  `master` changes every pipeline. Protect the branch.
- **Testing a library change**: `@Library('platform@my-branch') _` in one
  service's Jenkinsfile, on a branch.
