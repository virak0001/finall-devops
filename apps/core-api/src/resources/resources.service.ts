import { Injectable, NotFoundException, OnApplicationBootstrap } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Like } from 'typeorm';
import { Resource } from './resource.entity';
import { CreateResourceDto, UpdateResourceDto } from './dto/resource.dto';

const SEED_RESOURCES = [
  {
    title: 'OWASP Top 10',
    description:
      'The standard awareness document for web application security risks.',
    url: 'https://owasp.org/www-project-top-ten/',
    type: 'reference' as const,
    track: 'security',
    tags: ['security', 'owasp', 'web'],
  },
  {
    title: 'Docker Official Docs',
    description:
      'Complete Docker documentation including Compose, Swarm, and best practices.',
    url: 'https://docs.docker.com',
    type: 'reference' as const,
    track: 'foundation',
    tags: ['docker', 'containers', 'devops'],
  },
  {
    title: 'GitHub Actions Documentation',
    description:
      'Official guide for building CI/CD workflows with GitHub Actions.',
    url: 'https://docs.github.com/en/actions',
    type: 'reference' as const,
    track: 'ci-cd',
    tags: ['github-actions', 'ci-cd', 'automation'],
  },
  {
    title: 'Prometheus Querying (PromQL)',
    description: 'PromQL cheatsheet for writing effective monitoring queries.',
    url: 'https://prometheus.io/docs/prometheus/latest/querying/basics/',
    type: 'cheatsheet' as const,
    track: 'observability',
    tags: ['prometheus', 'promql', 'metrics'],
  },
  {
    title: 'Kubernetes Cheatsheet',
    description:
      'kubectl commands and manifest patterns for everyday cluster operations.',
    url: 'https://kubernetes.io/docs/reference/kubectl/cheatsheet/',
    type: 'cheatsheet' as const,
    track: 'cloud-gitops',
    tags: ['kubernetes', 'kubectl', 'k8s'],
  },
  {
    title: 'Chaos Engineering — Principles',
    description: 'The original principles of chaos engineering from Netflix.',
    url: 'https://principlesofchaos.org',
    type: 'reference' as const,
    track: 'resilience',
    tags: ['chaos', 'resilience', 'sre'],
  },
  {
    title: 'Trivy — Container Vulnerability Scanner',
    description:
      'Open-source vulnerability scanner for containers and filesystems.',
    url: 'https://github.com/aquasecurity/trivy',
    type: 'tool' as const,
    track: 'security',
    tags: ['scanning', 'security', 'containers'],
  },
  {
    title: 'gitleaks — Secret Detection',
    description: 'Fast secret detection tool for git repositories.',
    url: 'https://github.com/gitleaks/gitleaks',
    type: 'tool' as const,
    track: 'security',
    tags: ['secrets', 'git', 'security'],
  },
  {
    title: 'ArgoCD Docs',
    description: 'GitOps continuous delivery tool for Kubernetes.',
    url: 'https://argo-cd.readthedocs.io',
    type: 'reference' as const,
    track: 'cloud-gitops',
    tags: ['argocd', 'gitops', 'kubernetes'],
  },
  {
    title: 'DORA Metrics',
    description:
      'The four key metrics to measure software delivery performance.',
    url: 'https://dora.dev/research/',
    type: 'article' as const,
    track: 'ci-cd',
    tags: ['dora', 'metrics', 'performance'],
  },
  {
    title: 'OpenTelemetry Docs',
    description:
      'Vendor-neutral observability framework for traces, metrics, and logs.',
    url: 'https://opentelemetry.io/docs/',
    type: 'reference' as const,
    track: 'observability',
    tags: ['otel', 'tracing', 'observability'],
  },
  {
    title: 'Bash Scripting Guide',
    description: 'Comprehensive guide to writing robust Bash scripts.',
    url: 'https://www.gnu.org/software/bash/manual/bash.html',
    type: 'reference' as const,
    track: 'foundation',
    tags: ['bash', 'scripting', 'linux'],
  },
];

@Injectable()
export class ResourcesService implements OnApplicationBootstrap {
  constructor(
    @InjectRepository(Resource)
    private readonly resourceRepo: Repository<Resource>,
  ) {}

  async onApplicationBootstrap() {
    const count = await this.resourceRepo.count();
    if (count === 0) {
      for (const r of SEED_RESOURCES) {
        await this.resourceRepo.save(this.resourceRepo.create(r));
      }
    }
  }

  async findAll(track?: string, type?: string, search?: string) {
    const qb = this.resourceRepo
      .createQueryBuilder('r')
      .orderBy('r.createdAt', 'DESC');
    if (track) qb.andWhere('r.track = :track', { track });
    if (type) qb.andWhere('r.type = :type', { type });
    if (search) {
      qb.andWhere('(r.title ILIKE :q OR r.description ILIKE :q)', {
        q: `%${search}%`,
      });
    }
    return qb.getMany();
  }

  async findOne(id: string) {
    const resource = await this.resourceRepo.findOne({ where: { id } });
    if (!resource) throw new NotFoundException(`Resource ${id} not found`);
    return resource;
  }

  async create(dto: CreateResourceDto) {
    const resource = this.resourceRepo.create(dto);
    return this.resourceRepo.save(resource);
  }

  async update(id: string, dto: UpdateResourceDto) {
    const resource = await this.resourceRepo.findOne({ where: { id } });
    if (!resource) throw new NotFoundException(`Resource ${id} not found`);
    Object.assign(resource, dto);
    return this.resourceRepo.save(resource);
  }

  async remove(id: string) {
    const resource = await this.resourceRepo.findOne({ where: { id } });
    if (!resource) throw new NotFoundException(`Resource ${id} not found`);
    await this.resourceRepo.remove(resource);
    return { deleted: true };
  }
}
