<template>
    <div class="flex flex-col gap-6">
        <div>
            <h2 class="text-2xl font-bold text-highlighted">Welcome back</h2>
            <p class="text-sm text-muted mt-0.5">Here's your DevOps learning overview</p>
        </div>

        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <template v-if="dashLoading">
                <UCard v-for="i in 4" :key="i">
                    <div class="flex items-start justify-between">
                        <div class="flex-1">
                            <USkeleton class="h-3 w-20 rounded" />
                            <USkeleton class="h-8 w-12 rounded mt-2" />
                        </div>
                        <USkeleton class="size-9 rounded-xl shrink-0" />
                    </div>
                </UCard>
            </template>
            <template v-else>
                <UCard v-for="stat in statCards" :key="stat.label">
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
            </template>
        </div>

        <!-- Main grid -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Track progress -->
            <UCard class="lg:col-span-2">
                <template #header>
                    <div class="flex items-center justify-between">
                        <h3 class="font-semibold text-highlighted">Learning Tracks</h3>
                        <NuxtLink to="/learn">
                            <UButton variant="ghost" color="neutral" size="xs" trailing-icon="i-heroicons-arrow-right">
                                View all
                            </UButton>
                        </NuxtLink>
                    </div>
                </template>

                <div v-if="tracksLoading" class="flex flex-col gap-4">
                    <USkeleton v-for="i in 4" :key="i" class="h-12 rounded-lg" />
                </div>
                <div v-else class="flex flex-col gap-4">
                    <div v-for="track in tracksWithProgress" :key="track.trackSlug" class="flex items-center gap-4">
                        <div
                            :class="['flex size-9 shrink-0 items-center justify-center rounded-xl text-white text-sm font-bold', trackColor(track.trackSlug)]">
                            <UIcon :name="track.icon || 'i-heroicons-academic-cap'" class="size-4" />
                        </div>
                        <div class="min-w-0 flex-1">
                            <div class="flex items-center justify-between mb-1">
                                <NuxtLink :to="`/learn/${track.trackSlug}`"
                                    class="text-sm font-medium text-highlighted hover:text-primary truncate">
                                    {{ track.title }}
                                </NuxtLink>
                                <span class="ml-2 shrink-0 text-xs text-muted">
                                    {{ trackProgressMap[track.trackSlug]?.completed ?? 0 }}/{{
                                        trackProgressMap[track.trackSlug]?.total ?? '?' }}
                                </span>
                            </div>
                            <div class="track-progress-bar">
                                <div class="track-progress-fill bg-primary"
                                    :style="{ width: `${trackProgressMap[track.trackSlug]?.percent ?? 0}%` }" />
                            </div>
                        </div>
                        <UBadge :color="levelColor(track.level)" variant="soft" size="xs"
                            class="shrink-0 hidden lg:block">
                            {{ track.level }}
                        </UBadge>
                    </div>
                </div>
            </UCard>

            <!-- Recent playbooks -->
            <UCard>
                <template #header>
                    <div class="flex items-center justify-between">
                        <h3 class="font-semibold text-highlighted">Recent Playbooks</h3>
                        <NuxtLink to="/playbooks">
                            <UButton variant="ghost" color="neutral" size="xs" trailing-icon="i-heroicons-arrow-right">
                                View all
                            </UButton>
                        </NuxtLink>
                    </div>
                </template>

                <div v-if="dashLoading" class="flex flex-col gap-3">
                    <USkeleton v-for="i in 4" :key="i" class="h-14 rounded-lg" />
                </div>
                <div v-else-if="!dashboard?.recentPlaybooks?.length"
                    class="flex flex-col items-center justify-center py-8 gap-2">
                    <UIcon name="i-heroicons-clipboard-document-list" class="size-8 text-muted" />
                    <p class="text-sm text-muted">No playbooks yet</p>
                    <NuxtLink to="/playbooks">
                        <UButton size="xs" variant="soft" color="primary">Create one</UButton>
                    </NuxtLink>
                </div>
                <div v-else class="flex flex-col gap-3">
                    <div v-for="pb in dashboard?.recentPlaybooks?.slice(0, 5)" :key="pb.id"
                        class="flex items-start gap-3 p-2 rounded-lg hover:bg-elevated/50 transition-colors">
                        <UIcon :name="statusIcon(pb.status)"
                            :class="['size-4 mt-0.5 shrink-0', statusColor(pb.status)]" />
                        <div class="min-w-0">
                            <p class="text-sm font-medium text-highlighted truncate">{{ pb.title }}</p>
                            <UBadge :color="categoryColor(pb.category)" variant="soft" size="xs" class="mt-1">
                                {{ pb.category }}
                            </UBadge>
                        </div>
                    </div>
                </div>
            </UCard>
        </div>

        <!-- Highlights info card -->
        <UCard v-if="dashboard?.highlights?.length"
            class="bg-linear-to-r from-teal-500/10 to-sky-500/10 border-teal-200 dark:border-teal-800">
            <div class="flex items-start gap-3">
                <UIcon name="i-heroicons-light-bulb" class="size-5 text-teal-600 dark:text-teal-400 mt-0.5 shrink-0" />
                <div>
                    <p class="text-sm font-semibold text-highlighted mb-1">Platform highlights</p>
                    <ul class="flex flex-col gap-1">
                        <li v-for="(h, i) in dashboard.highlights" :key="i"
                            class="text-sm text-default flex items-center gap-2">
                            <span class="size-1 rounded-full bg-teal-500 shrink-0" />{{ h }}
                        </li>
                    </ul>
                </div>
            </div>
        </UCard>
    </div>
</template>

<script setup lang="ts">
import type { DashboardResponse, Track, TrackProgress, TrackSlug } from '~/types/api';

definePageMeta({ middleware: 'auth' });

const { data: dashboard, pending: dashLoading } = useFetch<DashboardResponse>('/api/dashboard');
const { data: tracks, pending: tracksLoading } = useFetch<Track[]>('/api/learn/tracks');

const trackProgressMap = ref<Record<string, TrackProgress>>({});


const tracksWithProgress = computed(() => tracks.value ?? []);

const totalCompleted = computed(() =>
    Object.values(trackProgressMap.value).reduce((s, p) => s + p.completed, 0)
);

const statCards = computed(() => [
    {
        label: 'Playbooks', value: dashboard.value?.metrics?.totalPlaybooks ?? 0,
        icon: 'i-heroicons-clipboard-document-list', bg: 'bg-teal-100 dark:bg-teal-900/40', color: 'text-teal-600 dark:text-teal-400',
    },
    {
        label: 'Practicing', value: dashboard.value?.metrics?.practicing ?? 0,
        icon: 'i-heroicons-arrow-path', bg: 'bg-amber-100 dark:bg-amber-900/40', color: 'text-amber-600 dark:text-amber-400',
    },
    {
        label: 'Validated', value: dashboard.value?.metrics?.validated ?? 0,
        icon: 'i-heroicons-check-badge', bg: 'bg-emerald-100 dark:bg-emerald-900/40', color: 'text-emerald-600 dark:text-emerald-400',
    },
    {
        label: 'Lessons done', value: totalCompleted.value,
        icon: 'i-heroicons-academic-cap', bg: 'bg-sky-100 dark:bg-sky-900/40', color: 'text-sky-600 dark:text-sky-400',
    },
]);

function trackColor(slug: string) {
    const map: Record<string, string> = {
        'foundation': 'bg-slate-600', 'ci-cd': 'bg-teal-600',
        'security': 'bg-red-600', 'observability': 'bg-amber-600',
        'resilience': 'bg-purple-600', 'cloud-gitops': 'bg-sky-600',
    };
    return map[slug] ?? 'bg-primary';
}
function levelColor(level: string) {
    if (level === 'beginner') return 'success' as const;
    if (level === 'intermediate') return 'warning' as const;
    return 'error' as const;
}
function statusIcon(s: string) {
    if (s === 'validated') return 'i-heroicons-check-circle';
    if (s === 'practicing') return 'i-heroicons-arrow-path';
    return 'i-heroicons-clock';
}
function statusColor(s: string) {
    if (s === 'validated') return 'text-emerald-500';
    if (s === 'practicing') return 'text-teal-500';
    return 'text-slate-400';
}
function categoryColor(c: string) {
    const map: Record<string, 'primary' | 'warning' | 'error' | 'success' | 'info'> = {
        delivery: 'primary', observability: 'warning', resilience: 'success', security: 'error',
    };
    return map[c] ?? 'info';
}
</script>
