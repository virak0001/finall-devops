export const trackSlugs = [
  'foundation',
  'ci-cd',
  'security',
  'observability',
  'resilience',
  'cloud-gitops',
] as const;

export const lessonTypes = ['reading', 'lab', 'quiz'] as const;
export const difficultyLevels = [
  'beginner',
  'intermediate',
  'advanced',
] as const;

export type TrackSlug = (typeof trackSlugs)[number];
export type LessonType = (typeof lessonTypes)[number];
export type DifficultyLevel = (typeof difficultyLevels)[number];

export const trackMeta: Record<
  TrackSlug,
  { label: string; color: string; icon: string; description: string }
> = {
  foundation: {
    label: 'Foundation',
    color: '#3b82f6',
    icon: 'foundation',
    description:
      'Linux, Git, Bash scripting, Docker basics, and networking fundamentals.',
  },
  'ci-cd': {
    label: 'CI/CD Pipelines',
    color: '#2ec4b6',
    icon: 'ci-cd',
    description:
      'Jenkins, GitHub Actions, GitLab CI, build pipelines, and automated testing.',
  },
  security: {
    label: 'DevSecOps',
    color: '#ff9f1c',
    icon: 'security',
    description:
      'OWASP Top 10, SAST/DAST, secrets management, image scanning, and supply-chain security.',
  },
  observability: {
    label: 'Observability',
    color: '#a855f7',
    icon: 'observability',
    description:
      'Prometheus, Grafana, Loki, distributed tracing with OpenTelemetry.',
  },
  resilience: {
    label: 'Resilience',
    color: '#ef4444',
    icon: 'resilience',
    description:
      'Chaos engineering, runbooks, incident response, SLOs, and disaster recovery.',
  },
  'cloud-gitops': {
    label: 'Cloud & GitOps',
    color: '#eab308',
    icon: 'cloud-gitops',
    description:
      'Kubernetes, Terraform, Helm, ArgoCD, and multi-cloud deployments.',
  },
};
