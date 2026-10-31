<template>
    <div class="flex flex-col gap-6">
        <!-- Header -->
        <div>
            <h2 class="text-2xl font-bold text-highlighted">Resources</h2>
            <p class="text-sm text-muted mt-0.5">Curated tools, articles, and references for your learning</p>
        </div>

        <!-- Filter bar -->
        <div class="flex flex-col gap-3">
            <UInput v-model="search" placeholder="Search resources…" leading-icon="i-heroicons-magnifying-glass"
                size="md" :ui="{ root: 'max-w-sm' }" />

            <div class="flex flex-wrap gap-3">
                <!-- Type filter -->
                <div class="flex flex-wrap gap-1.5">
                    <UButton v-for="t in typeFilters" :key="t.value"
                        :variant="typeFilter === t.value ? 'solid' : 'soft'"
                        :color="typeFilter === t.value ? 'primary' : 'neutral'"
                        size="xs" class="capitalize" @click="typeFilter = t.value">
                        <UIcon v-if="t.icon" :name="t.icon" class="size-3 mr-1" />{{ t.label }}
                    </UButton>
                </div>

                <USeparator orientation="vertical" class="h-6 hidden sm:block" />

                <!-- Track filter -->
                <div class="flex flex-wrap gap-1.5">
                    <UButton v-for="tr in trackFilters" :key="tr.value"
                        :variant="trackFilter === tr.value ? 'solid' : 'soft'"
                        :color="trackFilter === tr.value ? 'primary' : 'neutral'"
                        size="xs" @click="trackFilter = tr.value">
                        {{ tr.label }}
                    </UButton>
                </div>
            </div>
        </div>

        <!-- Loading -->
        <div v-if="pending" class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-5">
            <USkeleton v-for="i in 6" :key="i" class="h-44 rounded-2xl" />
        </div>

        <!-- Results -->
        <div v-else-if="resources?.length" class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-5">
            <a v-for="r in resources" :key="r.id" :href="r.url" target="_blank" rel="noopener noreferrer"
                class="group focus:outline-none">
                <UCard class="h-full transition-shadow group-hover:shadow-lg" :ui="{ body: 'flex flex-col gap-3 h-full' }">
                    <div class="flex items-start justify-between gap-2">
                        <div class="flex items-center gap-2 min-w-0">
                            <div :class="['flex size-8 shrink-0 items-center justify-center rounded-lg', typeStyle(r.type).bg]">
                                <UIcon :name="typeStyle(r.type).icon" :class="['size-4', typeStyle(r.type).color]" />
                            </div>
                            <UBadge :color="typeStyle(r.type).badge" variant="soft" size="xs" class="capitalize shrink-0">
                                {{ r.type }}
                            </UBadge>
                        </div>
                        <UIcon name="i-heroicons-arrow-top-right-on-square"
                            class="size-4 text-muted shrink-0 opacity-0 group-hover:opacity-100 transition-opacity" />
                    </div>

                    <div class="flex-1">
                        <h3 class="font-semibold text-highlighted leading-snug group-hover:text-primary transition-colors">
                            {{ r.title }}
                        </h3>
                        <p v-if="r.description" class="mt-1 text-xs text-muted leading-relaxed line-clamp-3">
                            {{ r.description }}
                        </p>
                    </div>

                    <div class="flex flex-wrap gap-1.5 mt-auto">
                        <UBadge v-if="r.track" :color="trackColor(r.track)" variant="soft" size="xs">
                            {{ r.track }}
                        </UBadge>
                        <UBadge v-for="tag in r.tags?.slice(0, 3)" :key="tag" color="neutral" variant="soft" size="xs">
                            {{ tag }}
                        </UBadge>
                    </div>
                </UCard>
            </a>
        </div>

        <!-- Empty state -->
        <div v-else class="flex flex-col items-center justify-center py-20 gap-3 text-muted">
            <UIcon name="i-heroicons-link" class="size-12 opacity-30" />
            <p class="text-sm">No resources found</p>
            <UButton v-if="search || typeFilter !== 'all' || trackFilter !== 'all'" variant="soft" color="neutral"
                size="xs" @click="clearFilters">
                Clear filters
            </UButton>
        </div>
    </div>
</template>

<script setup lang="ts">
import type { Resource, ResourceType } from '~/types/api';

const search = ref('');
const typeFilter = ref('all');
const trackFilter = ref('all');

const query = computed(() => {
    const q: Record<string, string> = {};
    if (search.value.trim()) q.search = search.value.trim();
    if (typeFilter.value !== 'all') q.type = typeFilter.value;
    if (trackFilter.value !== 'all') q.track = trackFilter.value;
    return q;
});

const { data: resources, pending } = useFetch<Resource[]>('/api/resources', {
    query,
    watch: [query],
});

const typeFilters = [
    { label: 'All', value: 'all', icon: '' },
    { label: 'Tool', value: 'tool', icon: 'i-heroicons-wrench-screwdriver' },
    { label: 'Article', value: 'article', icon: 'i-heroicons-document-text' },
    { label: 'Cheatsheet', value: 'cheatsheet', icon: 'i-heroicons-clipboard-document' },
    { label: 'Video', value: 'video', icon: 'i-heroicons-play-circle' },
    { label: 'Reference', value: 'reference', icon: 'i-heroicons-book-open' },
];

const trackFilters = [
    { label: 'All tracks', value: 'all' },
    { label: 'Foundation', value: 'foundation' },
    { label: 'CI/CD', value: 'ci-cd' },
    { label: 'Security', value: 'security' },
    { label: 'Observability', value: 'observability' },
    { label: 'Resilience', value: 'resilience' },
    { label: 'Cloud & GitOps', value: 'cloud-gitops' },
];

function clearFilters() {
    search.value = '';
    typeFilter.value = 'all';
    trackFilter.value = 'all';
}

function typeStyle(type: string) {
    const map: Record<string, { icon: string; bg: string; color: string; badge: 'primary' | 'warning' | 'success' | 'error' | 'info' | 'neutral' }> = {
        tool: { icon: 'i-heroicons-wrench-screwdriver', bg: 'bg-teal-100 dark:bg-teal-900/40', color: 'text-teal-600 dark:text-teal-400', badge: 'primary' },
        article: { icon: 'i-heroicons-document-text', bg: 'bg-sky-100 dark:bg-sky-900/40', color: 'text-sky-600 dark:text-sky-400', badge: 'info' },
        cheatsheet: { icon: 'i-heroicons-clipboard-document', bg: 'bg-amber-100 dark:bg-amber-900/40', color: 'text-amber-600 dark:text-amber-400', badge: 'warning' },
        video: { icon: 'i-heroicons-play-circle', bg: 'bg-purple-100 dark:bg-purple-900/40', color: 'text-purple-600 dark:text-purple-400', badge: 'neutral' },
        reference: { icon: 'i-heroicons-book-open', bg: 'bg-emerald-100 dark:bg-emerald-900/40', color: 'text-emerald-600 dark:text-emerald-400', badge: 'success' },
    };
    return map[type] ?? { icon: 'i-heroicons-link', bg: 'bg-slate-100 dark:bg-slate-800', color: 'text-slate-500', badge: 'neutral' as const };
}

function trackColor(track: string) {
    const map: Record<string, 'primary' | 'warning' | 'error' | 'success' | 'info'> = {
        foundation: 'neutral' as any, 'ci-cd': 'primary', security: 'error',
        observability: 'warning', resilience: 'success', 'cloud-gitops': 'info',
    };
    return map[track] ?? 'neutral' as any;
}
</script>
