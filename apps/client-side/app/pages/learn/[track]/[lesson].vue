<template>
    <div class="flex flex-col gap-6 max-w-5xl">
        <!-- Loading skeleton -->
        <div v-if="pending" class="flex flex-col gap-4">
            <USkeleton class="h-7 w-48 rounded-lg" />
            <USkeleton class="h-96 rounded-xl" />
        </div>

        <!-- Error -->
        <UAlert v-else-if="error" color="error" variant="soft" icon="i-heroicons-exclamation-triangle"
            title="Lesson not found">
            <template #description>
                <NuxtLink :to="`/learn/${trackSlug}`" class="underline">Back to track</NuxtLink>
            </template>
        </UAlert>

        <!-- Lesson content -->
        <template v-else-if="lesson">
            <!-- Breadcrumb -->
            <div class="flex items-center gap-1.5 text-sm text-muted">
                <NuxtLink to="/learn" class="hover:text-primary transition-colors">Learn</NuxtLink>
                <UIcon name="i-heroicons-chevron-right" class="size-3.5" />
                <NuxtLink :to="`/learn/${trackSlug}`" class="capitalize hover:text-primary transition-colors">{{
                    trackSlug }}</NuxtLink>
                <UIcon name="i-heroicons-chevron-right" class="size-3.5" />
                <span class="text-default font-medium truncate">{{ lesson.title }}</span>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-[1fr_220px] gap-6 items-start">
                <!-- Main article -->
                <UCard :ui="{ body: 'p-6 flex flex-col gap-6' }">
                    <!-- Header -->
                    <div class="flex flex-col gap-2">
                        <div class="flex items-center gap-3">
                            <UBadge :color="lessonTypeColor(lesson.type)" variant="soft" size="sm"
                                class="uppercase tracking-wider">
                                {{ lesson.type }}
                            </UBadge>
                            <span class="flex items-center gap-1.5 text-sm text-muted">
                                <UIcon name="i-heroicons-clock" class="size-4" />
                                {{ lesson.durationMinutes }} min
                            </span>
                        </div>
                        <h1 class="text-2xl font-bold text-highlighted">{{ lesson.title }}</h1>
                    </div>

                    <!-- Rendered markdown content -->
                    <div class="lesson-prose min-w-0" v-html="renderedContent" />

                    <!-- Footer: complete + navigation -->
                    <div class="flex flex-col gap-4 pt-4 border-t border-default">
                        <!-- Complete button -->
                        <div>
                            <div v-if="isCompleted"
                                class="inline-flex items-center gap-2 text-sm font-semibold text-teal-600 dark:text-teal-400 bg-teal-50 dark:bg-teal-900/30 px-4 py-2 rounded-lg">
                                <UIcon name="i-heroicons-check-circle" class="size-4" />
                                Completed
                            </div>
                            <UButton v-else color="primary" :loading="completing" leading-icon="i-heroicons-check"
                                @click="markComplete">
                                Mark as Complete
                            </UButton>
                        </div>

                        <!-- Prev / Next navigation -->
                        <div class="flex items-center gap-3">
                            <UButton v-if="prevLesson" :to="`/learn/${trackSlug}/${prevLesson.slug}`" variant="outline"
                                color="neutral" size="sm" leading-icon="i-heroicons-arrow-left"
                                class="flex-1 sm:flex-none truncate">
                                <span class="truncate max-w-40">{{ prevLesson.title }}</span>
                            </UButton>
                            <div class="flex-1" />
                            <UButton v-if="nextLesson" :to="`/learn/${trackSlug}/${nextLesson.slug}`" variant="outline"
                                color="neutral" size="sm" trailing-icon="i-heroicons-arrow-right"
                                class="flex-1 sm:flex-none justify-end truncate">
                                <span class="truncate max-w-40">{{ nextLesson.title }}</span>
                            </UButton>
                        </div>
                    </div>
                </UCard>

                <!-- Sidebar -->
                <div class="flex flex-col gap-4 lg:sticky lg:top-4">
                <!-- Profile card -->
                <UCard :ui="{ body: 'p-4 flex flex-col gap-3' }">
                    <div class="flex items-center gap-3">
                        <UAvatar :alt="displayName" size="md" :ui="{ root: 'shrink-0 ring-2 ring-primary/20' }" />
                        <div class="min-w-0">
                            <p class="text-sm font-semibold text-highlighted truncate">{{ displayName }}</p>
                            <UBadge :color="role === 'admin' ? 'error' : 'primary'" variant="soft" size="xs">
                                <UIcon :name="role === 'admin' ? 'i-heroicons-shield-check' : 'i-heroicons-user'" class="size-3 mr-1" />
                                {{ role }}
                            </UBadge>
                        </div>
                    </div>
                    <div class="grid grid-cols-2 gap-2 pt-1 border-t border-default">
                        <div class="flex flex-col">
                            <span class="text-[10px] font-semibold uppercase tracking-wider text-muted">Completed</span>
                            <span class="text-xl font-bold text-highlighted">{{ progressList?.length ?? 0 }}</span>
                        </div>
                        <div class="flex flex-col">
                            <span class="text-[10px] font-semibold uppercase tracking-wider text-muted">Track</span>
                            <span class="text-sm font-medium text-default capitalize truncate">{{ trackSlug }}</span>
                        </div>
                    </div>
                    <NuxtLink to="/profile">
                        <UButton variant="soft" color="neutral" size="xs" block trailing-icon="i-heroicons-arrow-right">
                            View profile
                        </UButton>
                    </NuxtLink>
                </UCard>

                <!-- TOC sidebar -->
                <div v-if="headings.length">
                    <UCard :ui="{ body: 'p-4' }">
                        <p class="text-[11px] font-semibold uppercase tracking-[0.15em] text-muted mb-3">On this page
                        </p>
                        <nav class="flex flex-col gap-0.5">
                            <a v-for="h in headings" :key="h.id" :href="`#${h.id}`"
                                :class="['block text-sm py-1 rounded-md transition-colors hover:text-primary hover:bg-elevated/60 px-2',
                                    h.level === 1 ? 'font-semibold text-default' : h.level === 2 ? 'pl-4 text-muted' : 'pl-6 text-muted text-xs']">
                                {{ h.text }}
                            </a>
                        </nav>
                    </UCard>
                </div>

                </div>
            </div>
        </template>
    </div>
</template>

<script setup lang="ts">
import type { LessonDetail, LessonSummary, TrackDetail, TrackModule, UserProgress } from '../../../types/api';
import type { $Fetch } from 'ofetch';

const route = useRoute();
const trackSlug = computed(() => String(route.params.track));
const lessonSlug = computed(() => String(route.params.lesson));

definePageMeta({ middleware: 'auth' });

const { data: lesson, pending, error } = useFetch<LessonDetail>(
    () => `/api/learn/lessons/${lessonSlug.value}`,
);
const { data: track } = useFetch<TrackDetail>(() => `/api/learn/tracks/${trackSlug.value}`);
const { data: progressList, refresh: refreshProgress } = useFetch<UserProgress[]>('/api/learn/progress');

// Profile
const tokenCookie = useCookie('access_token');
const decodedPayload = computed(() => {
    if (!tokenCookie.value) return null;
    try {
        const [, payload] = tokenCookie.value.split('.');
        if (!payload) return null;
        return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
    } catch { return null; }
});
const email = computed<string>(() => decodedPayload.value?.email ?? '');
const role = computed<string>(() => decodedPayload.value?.role ?? 'learner');
const displayName = computed(() => email.value.split('@')[0] ?? 'Learner');

useHead(() => ({ title: lesson.value ? `${lesson.value.title} | DevSecOps Hub` : 'Lesson' }));

// Markdown rendering (simple — supports headings, bold, code blocks, tables, lists)
const renderedContent = computed(() => {
    if (!lesson.value?.content) return '';
    return renderMarkdown(lesson.value.content);
});

// Build table of contents from headings
const headings = computed(() => {
    if (!lesson.value?.content) return [];
    const result: Array<{ id: string; text: string; level: number }> = [];
    const lines = lesson.value.content.split('\n');
    for (const line of lines) {
        const m = line.match(/^(#{1,3})\s+(.+)/);
        if (m) {
            const text = m[2]?.trim();
            if (text) {
                const id = text.toLowerCase().replace(/[^a-z0-9]+/g, '-');
                result.push({ id, text, level: m[1]?.length || 0 });
            }
        }
    }
    return result;
});

// Adjacent lesson navigation
const allLessons = computed<LessonSummary[]>(() => {
    if (!track.value) return [];
    return track.value.modules
        .flatMap((m: TrackModule) => m.lessons)
        .sort((a: LessonSummary, b: LessonSummary) => a.order - b.order);
});

const currentIdx = computed(() =>
    allLessons.value.findIndex((l: LessonSummary) => l.slug === lessonSlug.value),
);
const prevLesson = computed(() =>
    currentIdx.value > 0 ? allLessons.value[currentIdx.value - 1] : null,
);
const nextLesson = computed(() =>
    currentIdx.value < allLessons.value.length - 1
        ? allLessons.value[currentIdx.value + 1]
        : null,
);

const isCompleted = computed(() =>
    (progressList.value ?? []).some((p: UserProgress) => p.lessonId === lesson.value?.id),
);

const completing = ref(false);

async function markComplete() {
    if (!lesson.value || isCompleted.value || completing.value) return;
    completing.value = true;
    try {
        const nuxtApp = useNuxtApp();
        await (nuxtApp.$fetch as $Fetch)(`/api/learn/lessons/${lesson.value.id}/complete`, { method: 'POST' });
        await refreshProgress();
    } catch {
        // ignore
    } finally {
        completing.value = false;
    }
}

// ─── Minimal markdown renderer ────────────────────────────────────────────────
// renderMarkdown, escapeHtml, slugify are auto-imported from ~/utils/markdown.ts

function lessonTypeColor(type: string): 'primary' | 'info' | 'success' | 'warning' | 'neutral' {
    const map: Record<string, 'primary' | 'info' | 'success' | 'warning'> = {
        theory: 'info', reading: 'info', lab: 'success', quiz: 'warning', project: 'primary',
    };
    return map[type] ?? 'neutral';
}
</script>

<style scoped>
/* Markdown prose rendered via v-html */
.lesson-prose :deep(h1),
.lesson-prose :deep(h2),
.lesson-prose :deep(h3) {
    font-weight: 700;
    color: var(--ui-text-highlighted);
    margin: 1.5rem 0 0.6rem;
    line-height: 1.3;
}

.lesson-prose :deep(h1) {
    font-size: 1.25rem;
    border-bottom: 1px solid var(--ui-border);
    padding-bottom: 0.4rem;
}

.lesson-prose :deep(h2) {
    font-size: 1.05rem;
}

.lesson-prose :deep(h3) {
    font-size: 0.95rem;
}

.lesson-prose :deep(p) {
    font-size: 0.9rem;
    color: var(--ui-text);
    line-height: 1.75;
    margin: 0 0 0.9rem;
}

.lesson-prose :deep(ul) {
    list-style: disc;
    padding-left: 1.5rem;
    margin: 0 0 1rem;
}

.lesson-prose :deep(li) {
    font-size: 0.9rem;
    color: var(--ui-text);
    line-height: 1.65;
    margin-bottom: 0.25rem;
}

.lesson-prose :deep(table) {
    width: 100%;
    border-collapse: collapse;
    margin: 1rem 0;
    font-size: 0.875rem;
}

.lesson-prose :deep(th) {
    background: var(--ui-bg-elevated);
    color: var(--ui-text-highlighted);
    font-weight: 600;
    padding: 0.5rem 0.75rem;
    text-align: left;
    border-bottom: 1px solid var(--ui-border);
}

.lesson-prose :deep(td) {
    padding: 0.45rem 0.75rem;
    border-bottom: 1px solid var(--ui-border-muted, var(--ui-border));
    color: var(--ui-text);
    vertical-align: top;
}

.lesson-prose :deep(pre.code-block) {
    background: #0d1117;
    color: #e6edf3;
    border: 1px solid #30363d;
    border-radius: 0.5rem;
    padding: 1rem 1.25rem;
    overflow-x: auto;
    overflow-y: auto;
    max-height: 480px;
    margin: 1rem 0;
    font-size: 0.85rem;
    white-space: pre;
    min-width: 0;
}

.lesson-prose :deep(code) {
    font-family: 'IBM Plex Mono', 'Fira Code', ui-monospace, monospace;
    font-size: 0.85em;
    white-space: pre;
    color: inherit;
}

.lesson-prose :deep(.inline-code) {
    background: var(--ui-primary-50, color-mix(in srgb, var(--ui-primary) 10%, transparent));
    color: var(--ui-primary-700, var(--ui-primary));
    padding: 0.1em 0.35em;
    border-radius: 0.25rem;
}

.dark .lesson-prose :deep(.inline-code) {
    background: color-mix(in srgb, var(--ui-primary) 15%, transparent);
    color: var(--ui-primary);
}

.lesson-prose :deep(strong) {
    color: var(--ui-text-highlighted);
    font-weight: 600;
}
</style>
