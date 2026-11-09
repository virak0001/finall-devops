import { Controller, Get, ServiceUnavailableException } from "@nestjs/common";
import { InjectDataSource } from "@nestjs/typeorm";
import { DataSource } from "typeorm";

/**
 * Liveness and readiness, which answer two different questions:
 *
 *   /health        is this process alive?      never touches the database
 *   /health/ready  can it serve traffic?       requires the database
 *
 * The split matters. Liveness failing makes the kubelet KILL the container, so
 * checking the database there turns a brief Neon blip into a restart loop —
 * restarting the process does nothing to fix a database that is down. Readiness
 * failing only removes the pod from the Service, which is exactly what should
 * happen while it cannot reach its database.
 *
 * Paths are the ones the Helm chart probes by default (helm/values/
 * api-service/services.yaml: probes.path and probes.readyPath). Serving them
 * here rather than repointing the chart keeps every API in the group on one
 * convention.
 */
@Controller()
export class HealthController {
  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
  ) {}

  // Liveness. No dependencies on purpose — if the event loop is running enough
  // to answer this, the process is worth keeping.
  @Get("health")
  live() {
    return { status: "ok", service: "auth" };
  }

  // Readiness. `SELECT 1` is the cheapest round trip that proves the pool can
  // actually reach the database, rather than that a DataSource object exists.
  @Get("health/ready")
  async ready() {
    try {
      await this.dataSource.query("SELECT 1");
    } catch {
      // 503, not 500: this is "not ready yet", and the message is deliberately
      // vague — it is served unauthenticated, so it must not leak the host,
      // user or reason.
      throw new ServiceUnavailableException({
        status: "unavailable",
        service: "auth",
        reason: "database unreachable",
      });
    }

    return { status: "ok", service: "auth", database: "ok" };
  }

  // The original route, kept: the Dockerfile HEALTHCHECK calls it.
  @Get("api/health")
  health() {
    return { status: "ok", service: "auth" };
  }

  // The publicly reachable one. The ingress routes /api/auth here WITHOUT
  // rewriting, because this service serves the whole /api/auth path itself, so
  // a public health check has to live under that prefix too — /api/health is
  // not routed to this service at all.
  @Get("api/auth/health")
  publicHealth() {
    // Uptime shows a rollout from outside: it drops to seconds when new pods
    // take over. Nothing else about the process is exposed.
    return { status: "ok", service: "auth", uptimeSeconds: Math.round(process.uptime()) };
  }
}
