<template>
    <div class="flex flex-col gap-6">
        <!-- Breadcrumb -->
        <div class="flex items-center gap-2">
            <NuxtLink to="/learn">
                <UButton variant="ghost" color="neutral" size="xs" leading-icon="i-heroicons-arrow-left">
                    All Tracks
                </UButton>
            </NuxtLink>
        </div>

        <!-- Track hero -->
        <UCard v-if="track" :ui="{ body: 'flex flex-col gap-5' }">
            <div class="flex flex-col sm:flex-row items-start gap-5">
                <!-- Icon + progress ring -->
                <div class="relative shrink-0">
                    <svg class="size-20" viewBox="0 0 80 80">
                        <circle cx="40" cy="40" r="34" fill="none" stroke="currentColor" stroke-width="5"
                            class="text-elevated" />
                        <circle cx="40" cy="40" r="34" fill="none" :stroke-dasharray="circumference"
                            :stroke-dashoffset="dashOffset"
                            :class="['transition-all duration-700', ringStroke]"
                            stroke-width="5" stroke-linecap="round"
                            transform="rotate(-90 40 40)" />
                    </svg>
                    <div :class="['absolute inset-0 flex items-center justify-center rounded-full m-2', trackBg]">
                        <UIcon :name="track.icon || 'i-heroicons-academic-cap'" class="size-8 text-white" />
                    </div>
                </div>

                <div class="flex-1 min-w-0">
                    <div class="flex flex-wrap items-center gap-2 mb-1">
                        <h2 class="text-2xl font-bold text-highlighted">{{ track.title }}</h2>
                        <UBadge :color="levelColor(track.level)" variant="soft">{{ track.level }}</UBadge>
                    </div>
                    <p class="text-sm text-muted leading-relaxed">{{ track.description }}</p>
                    <div class="flex items-center gap-4 mt-3 text-sm text-muted">
                        <span class="flex items-center gap-1.5">
                            <UIcon name="i-heroicons-squares-2x2" class="size-4" />
                            {{ track.modules?.length ?? 0 }} modules
                        </span>
                        <span class="flex items-center gap-1.5">
                            <UIcon name="i-heroicons-check-circle" class="size-4 text-teal-500" />
                            {{ trackProgress?.completed ?? 0 }} / {{ trackProgress?.total ?? 0 }} lessons done
                        </span>
                        <span class="font-semibold text-highlighted">{{ trackProgress?.percent ?? 0 }}%</span>
                    </div>
                </div>
            </div>
        </UCard>

        <!-- Loading skeleton -->
        <div v-if="pending" class="flex flex-col gap-4">
            <USkeleton v-for="i in 4" :key="i" class="h-20 rounded-xl" />
        </div>

        <!-- Modules accordion -->
        <div v-else-if="track?.modules?.length" class="flex flex-col gap-3">
            <UCard v-for="mod in track.modules" :key="mod.id" :ui="{ body: 'p-0' }">
                <!-- Module header -->
                <button
                    class="w-full flex items-center justify-between px-4 py-3.5 text-left hover:bg-elevated/40 transition-colors rounded-xl"
                    @click="toggleModule(mod.id)">
                    <div class="flex items-center gap-3">
                        <div class="flex size-7 items-center justify-center rounded-lg bg-elevated text-xs font-bold text-muted">
                            {{ mod.order }}
                        </div>
                        <span class="font-semibold text-highlighted">{{ mod.title }}</span>
                        <UBadge color="neutral" variant="soft" size="xs">
                            {{ mod.lessons.length }} lessons
                        </UBadge>
                    </div>
                    <UIcon
                        :name="openModules.has(mod.id) ? 'i-heroicons-chevron-up' : 'i-heroicons-chevron-down'"
                        class="size-4 text-muted shrink-0 transition-transform" />
                </button>

                <!-- Lessons list -->
                <Transition name="slide-down">
                    <div v-if="openModules.has(mod.id)" class="border-t border-default">
                        <NuxtLink
                            v-for="(lesson, li) in mod.lessons"
                            :key="lesson.id"
                            :to="`/learn/${slug}/${lesson.slug}`"
                            :class="['flex items-center gap-3 px-4 py-3 text-sm hover:bg-elevated/50 transition-colors', li < mod.lessons.length - 1 ? 'border-b border-default' : '']">
                            <!-- Completion icon -->
                            <div :class="['flex size-6 shrink-0 items-center justify-center rounded-full transition-colors', completedIds.has(lesson.id) ? 'bg-teal-100 dark:bg-teal-900/40' : 'bg-elevated']">
                                <UIcon
                                    :name="completedIds.has(lesson.id) ? 'i-heroicons-check' : 'i-heroicons-minus'"
                                    :class="completedIds.has(lesson.id) ? 'size-3 text-teal-600 dark:text-teal-400' : 'size-3 text-muted'" />
                            </div>
                            <span :class="['flex-1 font-medium', completedIds.has(lesson.id) ? 'text-muted line-through' : 'text-default']">
                                {{ lesson.title }}
                            </span>
                            <UBadge :color="lessonTypeColor(lesson.type)" variant="soft" size="xs">
                                {{ lesson.type }}
                            </UBadge>
                            <span class="text-xs text-muted shrink-0">{{ lesson.durationMinutes }}m</span>
                            <UIcon name="i-heroicons-chevron-right" class="size-4 text-muted shrink-0" />
                        </NuxtLink>
                    </div>
                </Transition>
            </UCard>
        </div>

        <!-- Empty state -->
        <div v-else-if="!pending"
            class="flex flex-col items-center justify-center py-16 gap-3 text-muted">
            <UIcon name="i-heroicons-academic-cap" class="size-12 opacity-30" />
            <p class="text-sm">No modules available yet</p>
        </div>
    </div>
</template>

<script setup lang="ts">
import type { TrackDetail, TrackProgress, UserProgress } from '~/types/api';

definePageMeta({ middleware: 'auth' });

const route = useRoute();
const slug = computed(() => route.params.track as string);

const { data: track, pending } = useFetch<TrackDetail>(() => `/api/learn/tracks/${slug.value}`);
const { data: allProgress } = useFetch<UserProgress[]>('/api/learn/progress');
const { data: trackProgress } = useFetch<TrackProgress>(() => `/api/learn/progress/${slug.value}`);

const completedIds = computed(() => new Set((allProgress.value ?? []).map((p: UserProgress) => p.lessonId)));

const openModules = ref(new Set<string>());

function toggleModule(id: string) {
    if (openModules.value.has(id)) {
        openModules.value.delete(id);
    } else {
        openModules.value.add(id);
    }
    openModules.value = new Set(openModules.value);
}

// Auto-open first module
watch(track, (newVal) => {
    const t = newVal as TrackDetail | null | undefined;
    if (t?.modules?.[0]) openModules.value = new Set([t.modules[0].id]);
}, { immediate: true });

const circumference = 2 * Math.PI * 34;
const dashOffset = computed(() => circumference - (circumference * (trackProgress.value?.percent ?? 0)) / 100);

const trackBg = computed(() => {
    const map: Record<string, string> = {
        'foundation': 'bg-slate-600', 'ci-cd': 'bg-teal-600',
        'security': 'bg-red-600', 'observability': 'bg-amber-500',
        'resilience': 'bg-purple-600', 'cloud-gitops': 'bg-sky-600',
    };
    return map[slug.value] ?? 'bg-primary';
});
const ringStroke = computed(() => {
    const map: Record<string, string> = {
        'foundation': 'text-slate-500', 'ci-cd': 'text-teal-500',
        'security': 'text-red-500', 'observability': 'text-amber-500',
        'resilience': 'text-purple-500', 'cloud-gitops': 'text-sky-500',
    };
    return map[slug.value] ?? 'text-primary';
});

function levelColor(level: string) {
    if (level === 'beginner') return 'success' as const;
    if (level === 'intermediate') return 'warning' as const;
    return 'error' as const;
}
function lessonTypeColor(type: string) {
    const map: Record<string, 'primary' | 'warning' | 'error' | 'success' | 'info'> = {
        theory: 'info', lab: 'success', quiz: 'warning', project: 'primary',
    };
    return map[type] ?? 'neutral' as any;
}
</script>

<style scoped>
.slide-down-enter-active,
.slide-down-leave-active {
    transition: all 0.2s ease;
    overflow: hidden;
}
.slide-down-enter-from,
.slide-down-leave-to {
    max-height: 0;
    opacity: 0;
}
.slide-down-enter-to,
.slide-down-leave-from {
    max-height: 2000px;
    opacity: 1;
}
</style>
