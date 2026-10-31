# jenkins + sonarqube

One EC2 instance running Jenkins, SonarQube and SonarQube's database in Docker.

```bash
make init                     # once
make myip-set WORKSPACE=dev   # put your public IP in the allowlist
cp docker/.env.example docker/.env
$EDITOR docker/.env           # set SONAR_DB_PASSWORD

make up WORKSPACE=dev         # ~6 minutes
```

Then `make url` for the two addresses.

The pipelines it runs — webhooks, the shared library, build-once-promote,
approvals, rollback and the deployment record: [docs/pipelines.md](docs/pipelines.md).

---

## What it builds

```
        your IP only
             │
             ▼
    ┌────────────────────────────────┐
    │  m7i-flex.large  2 vCPU 8 GiB  │
    │  25 GB gp3, Elastic IP         │
    │                                │
    │   :8080  jenkins               │
    │   :9000  sonarqube ──► db      │
    │                     (postgres) │
    └────────────────────────────────┘
```

A VPC with one public subnet, an internet gateway, a security group and the
instance. **No NAT gateway and no load balancer** — both services need inbound
access anyway, so a private subnet would mean paying ~$33/month for NAT and
~$16/month for an ALB to reach a box only you use. The security group is the
boundary: SSH, 8080 and 9000 are open to `ssh_allowed_cidrs` and nothing else.

|           |                                                      |
| --------- | ---------------------------------------------------- |
| Instance  | `m7i-flex.large` — 2 vCPU, 8 GiB, Free Tier eligible |
| Volume    | 25 GB gp3, encrypted                                 |
| Address   | Elastic IP, so it survives stop/start                |
| Jenkins   | `jenkins/jenkins:lts-jdk21`                          |
| SonarQube | `sonarqube:26.8.0.126808-community`                  |
| Database  | `postgres:16-alpine`                                 |

## Money

| state          | monthly                                              |
| -------------- | ---------------------------------------------------- |
| running        | **~$75** — $69 instance, $2 volume, $3.65 Elastic IP |
| `make pause`   | **~$6** — volume and address only                    |
| `make destroy` | **$0**                                               |

`make pause` stops the instance and keeps the volume, so Jenkins jobs and
SonarQube history survive. The Elastic IP means the address is unchanged when
it comes back, which matters because Jenkins stores its own URL and
SonarQube's webhook points at it.

## Day to day

| command                       |                                                                 |
| ----------------------------- | --------------------------------------------------------------- |
| `make deploy`                 | copy `docker/` up and restart the stack — after editing compose |
| `make ps`                     | what is running                                                 |
| `make logs SERVICE=sonarqube` | follow one container                                            |
| `make ssh`                    | shell on the instance                                           |
| `make jenkins-password`       | the initial admin password                                      |
| `make pause` / `make resume`  | stop and start, keeping data                                    |

`make apply` builds the box; `make deploy` is everything after. The instance is
never rebuilt on purpose — rebuilding it loses every Jenkins job and all
SonarQube history, so `user_data` does only what must happen before Docker can
run, and `lifecycle { ignore_changes = [ami] }` stops a newer Ubuntu AMI
quietly proposing to replace it.

## Three things that will bite you

**SonarQube needs `vm.max_map_count=262144`.** It embeds Elasticsearch, which
refuses to start below that. cloud-init sets it on the host, because a
container cannot raise it. If SonarQube restarts in a loop, check this first:

```bash
make ssh
sysctl vm.max_map_count      # must be 262144
docker compose -f /opt/ci/docker-compose.yml logs sonarqube
```

**SonarQube will not run on its embedded database.** H2 is evaluation-only and
has no upgrade path, which is why `db` exists. `SONAR_DB_PASSWORD` is read from
`docker/.env` at first boot and written into the Postgres volume — changing it
afterwards means SonarQube can no longer open its own database.

**Jenkins gets the host's Docker socket.** That is what lets a pipeline run
`docker build` without docker-in-docker, and it is root-equivalent access to
the instance. Acceptable here because only your IP can reach this Jenkins; it
would not be on a shared box.

## Access is one allowlist

`ssh_allowed_cidrs` gates SSH, Jenkins and SonarQube together. A stale entry
does not error — the security group _drops_ the packets rather than refusing
them, so the browser hangs and SSH times out with nothing explaining why.

```bash
make myip       # does it still match? (exits non-zero if not)
make myip-set   # rewrite it, then: make apply
```

`0.0.0.0/0` is rejected by a variable validation. An internet-facing Jenkins is
a cryptominer with extra steps.

## Which AWS account

`aws_account_id` in `terraform/env/dev.tfvars` is checked on every plan.
Changing credentials otherwise does not fail — it succeeds against the wrong
account, finds nothing in state, and builds a second copy of everything while
the first keeps billing.

```bash
aws sts get-caller-identity --query Account --output text
```
