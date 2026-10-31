<template>
    <div class="flex flex-col gap-6">
        <!-- Profile header card -->
        <UCard :ui="{ body: 'flex flex-col sm:flex-row items-start sm:items-center gap-5' }">
            <UAvatar :alt="displayName" size="3xl"
                :ui="{ root: 'shrink-0 ring-4 ring-primary/20' }" />
            <div class="flex-1 min-w-0">
                <h2 class="text-2xl font-bold text-highlighted">{{ displayName }}</h2>
                <p class="text-sm text-muted mt-0.5">{{ email }}</p>
                <div class="flex flex-wrap gap-2 mt-3">
                    <UBadge :color="roleColor" variant="soft">
                        <UIcon :name="roleIcon" class="size-3 mr-1" />{{ role }}
                    </UBadge>
                    <UBadge v-if="tracksCompleted > 0" color="success" variant="soft">
                        <UIcon name="i-heroicons-trophy" class="size-3 mr-1" />
                        {{ tracksCompleted }} track{{ tracksCompleted > 1 ? 's' : '' }} completed
                    </UBadge>
                    <UBadge v-if="totalCompleted >= 10" color="primary" variant="soft">
                        <UIcon name="i-heroicons-star" class="size-3 mr-1" />Active learner
                    </UBadge>
                </div>
            </div>
        </UCard>

        <!-- Stats row -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <UCard v-for="stat in stats" :key="stat.label">
                <div class="flex items-start justify-between">
                    <div>
                        <p class="text-xs font-medium text-muted uppercase tracking-wide">{{ stat.label }}</p>
                        <p class="text-3xl font-bold text-highlighted mt-1">{{ stat.value }}</p>
                    </div>
                    <div :class="['flex size-9 items-center justify-center rounded-xl', stat.bg]">
                        <UIcon :name="stat.icon" :class="['size-5', stat.color]" />
                    </div>
                </div>
            </UCard>
        </div>

        <!-- Content grid -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Track progress -->
            <UCard class="lg:col-span-2">
                <template #header>
                    <h3 class="font-semibold text-highlighted">Track Progress</h3>
                </template>

                <div v-if="progressLoading" class="flex flex-col gap-4">
                    <USkeleton v-for="i in 6" :key="i" class="h-10 rounded-lg" />
                </div>
                <div v-else class="flex flex-col gap-4">
                    <div v-for="(tp, slug) in trackProgressMap" :key="slug" class="flex items-center gap-4">
                        <div :class="['flex size-8 shrink-0 items-center justify-center rounded-lg text-white', trackBg(slug)]">
                            <UIcon :name="trackIcon(slug)" class="size-4" />
                        </div>
                        <div class="flex-1 min-w-0">
                            <div class="flex items-center justify-between mb-1">
                                <NuxtLink :to="`/learn/${slug}`"
                                    class="text-sm font-medium text-highlighted hover:text-primary truncate">
                                    {{ trackLabel(slug) }}
                                </NuxtLink>
                                <span class="ml-2 shrink-0 text-xs text-muted">
                                    {{ tp.completed }}/{{ tp.total }}
                                </span>
                            </div>
                            <div class="track-progress-bar">
                                <div :class="['track-progress-fill', tp.percent >= 100 ? 'bg-emerald-500' : 'bg-primary']"
                                    :style="{ width: `${tp.percent}%` }" />
                            </div>
                        </div>
                        <span class="shrink-0 text-xs font-semibold text-muted w-10 text-right">{{ tp.percent }}%</span>
                    </div>
                </div>
            </UCard>

            <!-- Achievements -->
            <UCard>
                <template #header>
                    <h3 class="font-semibold text-highlighted">Achievements</h3>
                </template>

                <div class="flex flex-col gap-3">
                    <div v-for="ach in achievements" :key="ach.id"
                        :class="['flex items-center gap-3 p-2.5 rounded-xl', ach.unlocked ? 'bg-elevated/60' : 'opacity-40']">
                        <div :class="['flex size-9 shrink-0 items-center justify-center rounded-xl', ach.unlocked ? ach.bg : 'bg-elevated']">
                            <UIcon :name="ach.icon" :class="['size-5', ach.unlocked ? ach.color : 'text-muted']" />
                        </div>
                        <div class="min-w-0">
                            <p class="text-sm font-medium text-highlighted truncate">{{ ach.label }}</p>
                            <p class="text-xs text-muted">{{ ach.desc }}</p>
                        </div>
                        <UIcon v-if="ach.unlocked" name="i-heroicons-check-badge"
                            class="size-4 text-teal-500 shrink-0" />
                    </div>
                </div>
            </UCard>
        </div>
    </div>
</template>

<script setup lang="ts">
import type { UserProgress, TrackProgress } from '~/types/api';

definePageMeta({ middleware: 'auth' });

// Decode JWT to get user info
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

const roleColor = computed(() => role.value === 'admin' ? 'error' as const : 'primary' as const);
const roleIcon = computed(() => role.value === 'admin' ? 'i-heroicons-shield-check' : 'i-heroicons-user');

const { data: allProgress, pending: progressLoading } = useFetch<UserProgress[]>('/api/learn/progress');

const trackSlugs = ['foundation', 'ci-cd', 'security', 'observability', 'resilience', 'cloud-gitops'] as const;
const trackProgressMap = ref<Record<string, TrackProgress>>({});

onMounted(async () => {
    await Promise.all(trackSlugs.map(async (slug) => {
        try {
            const p = await $fetch<TrackProgress>(`/api/learn/progress/${slug}`);
            trackProgressMap.value[slug] = p;
        } catch {
            trackProgressMap.value[slug] = { total: 0, completed: 0, percent: 0 };
        }
    }));
});

const totalCompleted = computed(() =>
    Object.values(trackProgressMap.value).reduce((s, p) => s + p.completed, 0)
);
const tracksStarted = computed(() =>
    Object.values(trackProgressMap.value).filter(p => p.completed > 0).length
);
const tracksCompleted = computed(() =>
    Object.values(trackProgressMap.value).filter(p => p.percent >= 100).length
);
const overallPercent = computed(() => {
    const vals = Object.values(trackProgressMap.value);
    if (!vals.length) return 0;
    return Math.round(vals.reduce((s, p) => s + p.percent, 0) / vals.length);
});

const stats = computed(() => [
    {
        label: 'Lessons done', value: totalCompleted.value,
        icon: 'i-heroicons-check-circle', bg: 'bg-teal-100 dark:bg-teal-900/40', color: 'text-teal-600 dark:text-teal-400',
    },
    {
        label: 'Tracks started', value: tracksStarted.value,
        icon: 'i-heroicons-academic-cap', bg: 'bg-sky-100 dark:bg-sky-900/40', color: 'text-sky-600 dark:text-sky-400',
    },
    {
        label: 'Tracks completed', value: tracksCompleted.value,
        icon: 'i-heroicons-trophy', bg: 'bg-amber-100 dark:bg-amber-900/40', color: 'text-amber-600 dark:text-amber-400',
    },
    {
        label: 'Overall progress', value: `${overallPercent.value}%`,
        icon: 'i-heroicons-chart-bar', bg: 'bg-purple-100 dark:bg-purple-900/40', color: 'text-purple-600 dark:text-purple-400',
    },
]);

const achievements = computed(() => [
    {
        id: 'first-lesson', label: 'First Steps', desc: 'Complete your first lesson',
        icon: 'i-heroicons-sparkles', bg: 'bg-teal-100 dark:bg-teal-900/40', color: 'text-teal-600 dark:text-teal-400',
        unlocked: totalCompleted.value >= 1,
    },
    {
        id: 'ten-lessons', label: 'On a Roll', desc: 'Complete 10 lessons',
        icon: 'i-heroicons-bolt', bg: 'bg-amber-100 dark:bg-amber-900/40', color: 'text-amber-600 dark:text-amber-400',
        unlocked: totalCompleted.value >= 10,
    },
    {
        id: 'track-started', label: 'Explorer', desc: 'Start 3 or more tracks',
        icon: 'i-heroicons-map', bg: 'bg-sky-100 dark:bg-sky-900/40', color: 'text-sky-600 dark:text-sky-400',
        unlocked: tracksStarted.value >= 3,
    },
    {
        id: 'track-complete', label: 'Track Master', desc: 'Complete a full track',
        icon: 'i-heroicons-trophy', bg: 'bg-emerald-100 dark:bg-emerald-900/40', color: 'text-emerald-600 dark:text-emerald-400',
        unlocked: tracksCompleted.value >= 1,
    },
    {
        id: 'all-tracks', label: 'DevOps Champion', desc: 'Complete all 6 tracks',
        icon: 'i-heroicons-star', bg: 'bg-purple-100 dark:bg-purple-900/40', color: 'text-purple-600 dark:text-purple-400',
        unlocked: tracksCompleted.value >= 6,
    },
]);

function trackBg(slug: string) {
    const map: Record<string, string> = {
        foundation: 'bg-slate-600', 'ci-cd': 'bg-teal-600',
        security: 'bg-red-600', observability: 'bg-amber-500',
        resilience: 'bg-purple-600', 'cloud-gitops': 'bg-sky-600',
    };
    return map[slug] ?? 'bg-primary';
}
function trackIcon(slug: string) {
    const map: Record<string, string> = {
        foundation: 'i-heroicons-circle-stack', 'ci-cd': 'i-heroicons-arrow-path-rounded-square',
        security: 'i-heroicons-shield-check', observability: 'i-heroicons-chart-bar-square',
        resilience: 'i-heroicons-bolt', 'cloud-gitops': 'i-heroicons-cloud',
    };
    return map[slug] ?? 'i-heroicons-academic-cap';
}
function trackLabel(slug: string) {
    const map: Record<string, string> = {
        foundation: 'Foundation', 'ci-cd': 'CI/CD',
        security: 'Security', observability: 'Observability',
        resilience: 'Resilience', 'cloud-gitops': 'Cloud & GitOps',
    };
    return map[slug] ?? slug;
}
</script>
