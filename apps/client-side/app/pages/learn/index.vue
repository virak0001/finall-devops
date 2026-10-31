<template>
    <div class="flex flex-col gap-6">
        <!-- Header -->
        <div>
            <h2 class="text-2xl font-bold text-highlighted">Learning Roadmap</h2>
            <p class="text-sm text-muted mt-0.5">Six structured tracks from Foundation to Cloud & GitOps</p>
        </div>

        <!-- Progress overview -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <UCard>
                <p class="text-xs font-medium text-muted uppercase tracking-wide">Tracks started</p>
                <p class="text-3xl font-bold text-highlighted mt-1">{{ tracksStarted }}</p>
                <p class="text-xs text-muted mt-0.5">of {{ tracks?.length ?? 6 }} tracks</p>
            </UCard>
            <UCard>
                <p class="text-xs font-medium text-muted uppercase tracking-wide">Lessons done</p>
                <p class="text-3xl font-bold text-highlighted mt-1">{{ totalCompleted }}</p>
            </UCard>
            <UCard>
                <p class="text-xs font-medium text-muted uppercase tracking-wide">Tracks completed</p>
                <p class="text-3xl font-bold text-highlighted mt-1">{{ tracksCompleted }}</p>
            </UCard>
            <UCard>
                <p class="text-xs font-medium text-muted uppercase tracking-wide">Overall progress</p>
                <p class="text-3xl font-bold text-highlighted mt-1">{{ overallPercent }}%</p>
            </UCard>
        </div>

        <!-- Track cards grid -->
        <div v-if="pending" class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-5">
            <USkeleton v-for="i in 6" :key="i" class="h-52 rounded-2xl" />
        </div>
        <div v-else class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-5">
            <NuxtLink v-for="track in tracks" :key="track.trackSlug" :to="`/learn/${track.trackSlug}`"
                class="group focus:outline-none">
                <UCard class="h-full transition-shadow group-hover:shadow-lg"
                    :ui="{ root: 'overflow-hidden', body: 'flex flex-col gap-3 h-full' }">
                    <!-- Colored top bar -->
                    <div :class="['h-1.5 -mx-4 -mt-4 mb-1 rounded-t-xl', trackBg(track.trackSlug)]" />

                    <div class="flex items-start gap-3">
                        <div :class="['flex size-10 shrink-0 items-center justify-center rounded-xl text-white shadow-sm', trackBg(track.trackSlug)]">
                            <UIcon :name="track.icon || 'i-heroicons-academic-cap'" class="size-5" />
                        </div>
                        <div class="min-w-0">
                            <h3 class="font-semibold text-highlighted truncate group-hover:text-primary transition-colors">
                                {{ track.title }}
                            </h3>
                            <UBadge :color="levelColor(track.level)" variant="soft" size="xs" class="mt-0.5">
                                {{ track.level }}
                            </UBadge>
                        </div>
                    </div>

                    <p class="text-sm text-muted leading-relaxed line-clamp-3 flex-1">{{ track.description }}</p>

                    <!-- Progress bar -->
                    <div>
                        <div class="flex items-center justify-between mb-1.5">
                            <span class="text-xs text-muted">Progress</span>
                            <span class="text-xs font-medium text-highlighted">
                                {{ trackProgressMap[track.trackSlug]?.completed ?? 0 }} / {{ trackProgressMap[track.trackSlug]?.total ?? '?' }}
                            </span>
                        </div>
                        <div class="track-progress-bar">
                            <div :class="['track-progress-fill', trackBg(track.trackSlug)]"
                                :style="{ width: `${trackProgressMap[track.trackSlug]?.percent ?? 0}%` }" />
                        </div>
                    </div>
                </UCard>
            </NuxtLink>
        </div>
    </div>
</template>

<script setup lang="ts">
import type { Track, TrackProgress } from '~/types/api';

definePageMeta({ middleware: 'auth' });

const { data: tracks, pending } = useFetch<Track[]>('/api/learn/tracks');

const trackProgressMap = ref<Record<string, TrackProgress>>({});

onMounted(async () => {
    const list = tracks.value ?? [];
    await Promise.all(list.map(async (track: Track) => {
        try {
            const p = await $fetch<TrackProgress>(`/api/learn/progress/${track.trackSlug}`);
            trackProgressMap.value[track.trackSlug] = p;
        } catch {
            trackProgressMap.value[track.trackSlug] = { total: 0, completed: 0, percent: 0 };
        }
    }));
});

const totalCompleted = computed(() =>
    (Object.values(trackProgressMap.value) as TrackProgress[]).reduce((s, p) => s + p.completed, 0)
);
const tracksStarted = computed(() =>
    (Object.values(trackProgressMap.value) as TrackProgress[]).filter(p => p.completed > 0).length
);
const tracksCompleted = computed(() =>
    (Object.values(trackProgressMap.value) as TrackProgress[]).filter(p => p.percent >= 100).length
);
const overallPercent = computed(() => {
    const vals = Object.values(trackProgressMap.value) as TrackProgress[];
    if (!vals.length) return 0;
    const avg = vals.reduce((s, p) => s + p.percent, 0) / vals.length;
    return Math.round(avg);
});

function trackBg(slug: string) {
    const map: Record<string, string> = {
        'foundation': 'bg-slate-600', 'ci-cd': 'bg-teal-600',
        'security': 'bg-red-600', 'observability': 'bg-amber-500',
        'resilience': 'bg-purple-600', 'cloud-gitops': 'bg-sky-600',
    };
    return map[slug] ?? 'bg-primary';
}
function levelColor(level: string) {
    if (level === 'beginner') return 'success' as const;
    if (level === 'intermediate') return 'warning' as const;
    return 'error' as const;
}
</script>
