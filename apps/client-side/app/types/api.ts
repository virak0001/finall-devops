export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegisterRequest {
  email: string;
  password: string;
  firstName?: string;
  lastName?: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

export interface AuthUser {
  id: string;
  email: string;
  role: string;
}

export interface LoginResponse {
  user: AuthUser;
  accessToken: string;
  refreshToken: string;
}

export type PlaybookCategory =
  | "delivery"
  | "observability"
  | "resilience"
  | "security";

export type PlaybookDifficulty = "intermediate" | "advanced";

export type PlaybookStatus = "planned" | "practicing" | "validated";

export interface Playbook {
  id: string;
  title: string;
  description: string;
  category: PlaybookCategory;
  difficulty: PlaybookDifficulty;
  status: PlaybookStatus;
  createdAt: string;
  updatedAt: string;
}

export interface CreatePlaybookPayload {
  title: string;
  description: string;
  category: PlaybookCategory;
  difficulty: PlaybookDifficulty;
  status: PlaybookStatus;
}

export interface DashboardResponse {
  appName: string;
  environment: string;
  generatedAt: string;
  tagline: string;
  highlights: string[];
  commands: {
    compose: string;
    swarm: string;
  };
  metrics: {
    totalPlaybooks: number;
    practicing: number;
    validated: number;
    learningTracks: number;
  };
  categories: Array<{
    key: PlaybookCategory;
    label: string;
    total: number;
  }>;
  recentPlaybooks: Playbook[];
}

// ─── Learn Platform ──────────────────────────────────────────────────────────

export type TrackSlug =
  | "foundation"
  | "ci-cd"
  | "security"
  | "observability"
  | "resilience"
  | "cloud-gitops";

export type LessonType = "theory" | "lab" | "quiz" | "project";
export type DifficultyLevel = "beginner" | "intermediate" | "advanced";
export type ResourceType =
  | "tool"
  | "article"
  | "cheatsheet"
  | "video"
  | "reference";

export interface LessonSummary {
  id: string;
  title: string;
  slug: string;
  type: LessonType;
  durationMinutes: number;
  order: number;
}

export interface TrackModule {
  id: string;
  title: string;
  order: number;
  lessons: LessonSummary[];
}

export interface Track {
  id: string;
  trackSlug: TrackSlug;
  title: string;
  description: string;
  level: DifficultyLevel;
  color: string;
  icon: string;
  order: number;
}

export interface TrackDetail extends Track {
  modules: TrackModule[];
  lessonCount?: number;
}

export interface LessonDetail extends LessonSummary {
  content: string;
}

export interface UserProgress {
  id: string;
  userId: string;
  lessonId: string;
  completedAt: string;
}

export interface TrackProgress {
  total: number;
  completed: number;
  percent: number;
}

export interface Resource {
  id: string;
  title: string;
  description: string;
  url: string;
  type: ResourceType;
  track: string;
  tags: string[];
  createdAt: string;
}

// ─── Admin Learn ─────────────────────────────────────────────────────────────

export interface AdminLessonDetail {
  id: string;
  moduleId: string;
  title: string;
  slug: string;
  content: string;
  type: string;
  durationMinutes: number;
  order: number;
  labConfig?: string;
}

export interface CreateLessonPayload {
  title: string;
  slug: string;
  moduleId: string;
  type: string;
  content: string;
  durationMinutes: number;
  order: number;
  labConfig?: string;
}

export interface UpdateLessonPayload {
  title?: string;
  slug?: string;
  type?: string;
  content?: string;
  durationMinutes?: number;
  order?: number;
  labConfig?: string;
}

export interface CreateModulePayload {
  courseId: string;
  title: string;
  order: number;
  description?: string;
}

export interface UpdateModulePayload {
  title?: string;
  order?: number;
  description?: string;
}

export interface CreateTrackPayload {
  trackSlug: string;
  title: string;
  description: string;
  level: DifficultyLevel;
  color?: string;
  icon?: string;
  order?: number;
}

export interface UpdateTrackPayload {
  trackSlug?: string;
  title?: string;
  description?: string;
  level?: DifficultyLevel;
  color?: string;
  icon?: string;
  order?: number;
}

// ─── Admin Playbooks ──────────────────────────────────────────────────────────

export interface UpdatePlaybookPayload {
  title?: string;
  description?: string;
  category?: PlaybookCategory;
  difficulty?: PlaybookDifficulty;
  status?: PlaybookStatus;
}

// ─── Admin Resources ──────────────────────────────────────────────────────────

export interface CreateResourcePayload {
  title: string;
  description: string;
  url: string;
  type: ResourceType;
  track: string;
  tags?: string[];
}

export interface UpdateResourcePayload {
  title?: string;
  description?: string;
  url?: string;
  type?: ResourceType;
  track?: string;
  tags?: string[];
}

// ─── Blog ────────────────────────────────────────────────────────────────────

export interface BlogPost {
  id: string;
  title: string;
  slug: string;
  content: string;
  createdAt: string;
  updatedAt: string;
}

export interface BlogComment {
  id: string;
  postId: string;
  authorName: string;
  authorEmail: string;
  content: string;
  createdAt: string;
}

export interface CreateBlogPostPayload {
  title: string;
  content: string;
}

export interface UpdateBlogPostPayload {
  title?: string;
  content?: string;
}

export interface CreateBlogCommentPayload {
  content: string;
}

export interface BlogCompletion {
  id: string;
  userId: string;
  postId: string;
  createdAt: string;
}
