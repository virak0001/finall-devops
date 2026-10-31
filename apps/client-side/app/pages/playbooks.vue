<template>
    <div class="flex flex-col gap-6">
        <!-- Header -->
        <div class="flex items-center justify-between">
            <div>
                <h2 class="text-2xl font-bold text-highlighted">Playbooks</h2>
                <p class="text-sm text-muted mt-0.5">Practice and validate your DevOps techniques</p>
            </div>
            <UButton color="primary" leading-icon="i-heroicons-plus" @click="showForm = !showForm">
                New Playbook
            </UButton>
        </div>

        <!-- Create form (slide-in) -->
        <Transition name="slide-down">
            <UCard v-if="showForm">
                <template #header>
                    <div class="flex items-center justify-between">
                        <h3 class="font-semibold text-highlighted">Create Playbook</h3>
                        <UButton icon="i-heroicons-x-mark" size="xs" variant="ghost" color="neutral"
                            @click="showForm = false" />
                    </div>
                </template>

                <form class="grid grid-cols-1 sm:grid-cols-2 gap-4" @submit.prevent="submitPlaybook">
                    <UFormField label="Title" name="title" class="sm:col-span-2">
                        <UInput v-model="newPlaybook.title" placeholder="e.g. Zero-downtime deployment" size="lg"
                            :ui="{ root: 'w-full' }" required />
                    </UFormField>
                    <UFormField label="Description" name="description" class="sm:col-span-2">
                        <UTextarea v-model="newPlaybook.description" placeholder="What does this playbook cover?"
                            :rows="3" :ui="{ root: 'w-full' }" />
                    </UFormField>
                    <UFormField label="Category" name="category">
                        <USelect v-model="newPlaybook.category" :items="categoryOptions" size="lg"
                            :ui="{ root: 'w-full' }" />
                    </UFormField>
                    <UFormField label="Difficulty" name="difficulty">
                        <USelect v-model="newPlaybook.difficulty" :items="difficultyOptions" size="lg"
                            :ui="{ root: 'w-full' }" />
                    </UFormField>
                    <UFormField label="Status" name="status">
                        <USelect v-model="newPlaybook.status" :items="statusOptions" size="lg"
                            :ui="{ root: 'w-full' }" />
                    </UFormField>

                    <UAlert v-if="formError" color="error" variant="soft" class="sm:col-span-2" :ui="{ root: 'py-2' }">
                        {{ formError }}
                    </UAlert>

                    <div class="sm:col-span-2 flex justify-end gap-2">
                        <UButton variant="ghost" color="neutral" @click="showForm = false">Cancel</UButton>
                        <UButton type="submit" color="primary" :loading="submitting">Create</UButton>
                    </div>
                </form>
            </UCard>
        </Transition>

        <!-- Filter bar -->
        <div class="flex flex-wrap items-center gap-3">
            <UInput v-model="filterText" placeholder="Search playbooks…" leading-icon="i-heroicons-magnifying-glass"
                size="sm" :ui="{ root: 'w-48' }" />
            <div class="flex flex-wrap gap-1.5">
                <UButton v-for="cat in ['all', ...categoryOptions.map(c => c.value)]" :key="cat"
                    :variant="activeCategory === cat ? 'solid' : 'soft'"
                    :color="activeCategory === cat ? 'primary' : 'neutral'"
                    size="xs" class="capitalize" @click="activeCategory = cat">
                    {{ cat }}
                </UButton>
            </div>
        </div>

        <!-- Kanban columns -->
        <div v-if="loading" class="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <USkeleton v-for="i in 3" :key="i" class="h-64 rounded-2xl" />
        </div>
        <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <div v-for="col in columns" :key="col.status">
                <div class="flex items-center gap-2 mb-3">
                    <UIcon :name="col.icon" :class="['size-4', col.color]" />
                    <span class="text-sm font-semibold text-highlighted">{{ col.label }}</span>
                    <UBadge :color="col.badgeColor" variant="soft" size="xs">
                        {{ filteredByColumn(col.status).length }}
                    </UBadge>
                </div>

                <div class="flex flex-col gap-3">
                    <UCard v-for="pb in filteredByColumn(col.status)" :key="pb.id"
                        :ui="{ body: 'flex flex-col gap-2' }">
                        <p class="text-sm font-semibold text-highlighted leading-snug">{{ pb.title }}</p>
                        <p v-if="pb.description" class="text-xs text-muted leading-relaxed line-clamp-2">
                            {{ pb.description }}
                        </p>
                        <div class="flex flex-wrap items-center gap-1.5 mt-1">
                            <UBadge :color="categoryColor(pb.category)" variant="soft" size="xs">
                                {{ pb.category }}
                            </UBadge>
                            <UBadge :color="difficultyColor(pb.difficulty)" variant="soft" size="xs">
                                {{ pb.difficulty }}
                            </UBadge>
                        </div>
                    </UCard>

                    <!-- Empty column -->
                    <div v-if="!filteredByColumn(col.status).length"
                        class="flex flex-col items-center justify-center rounded-xl border border-dashed border-default py-10 text-muted gap-2">
                        <UIcon :name="col.icon" class="size-7 opacity-30" />
                        <p class="text-xs">No {{ col.label.toLowerCase() }} playbooks</p>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>

<script setup lang="ts">
import type { Playbook, CreatePlaybookPayload, PlaybookCategory, PlaybookDifficulty, PlaybookStatus } from '~/types/api';

definePageMeta({ middleware: 'auth' });

const { data: playbooks, pending: loading, refresh } = useFetch<Playbook[]>('/api/playbooks');

const showForm = ref(false);
const submitting = ref(false);
const formError = ref('');
const filterText = ref('');
const activeCategory = ref('all');

const newPlaybook = reactive<CreatePlaybookPayload>({
    title: '',
    description: '',
    category: 'delivery',
    difficulty: 'intermediate',
    status: 'planned',
});

const categoryOptions = [
    { label: 'Delivery', value: 'delivery' },
    { label: 'Observability', value: 'observability' },
    { label: 'Resilience', value: 'resilience' },
    { label: 'Security', value: 'security' },
];
const difficultyOptions = [
    { label: 'Intermediate', value: 'intermediate' },
    { label: 'Advanced', value: 'advanced' },
];
const statusOptions = [
    { label: 'Planned', value: 'planned' },
    { label: 'Practicing', value: 'practicing' },
    { label: 'Validated', value: 'validated' },
];

const columns = [
    { status: 'planned' as PlaybookStatus, label: 'Planned', icon: 'i-heroicons-clock', color: 'text-slate-400', badgeColor: 'neutral' as const },
    { status: 'practicing' as PlaybookStatus, label: 'Practicing', icon: 'i-heroicons-arrow-path', color: 'text-teal-500', badgeColor: 'primary' as const },
    { status: 'validated' as PlaybookStatus, label: 'Validated', icon: 'i-heroicons-check-circle', color: 'text-emerald-500', badgeColor: 'success' as const },
];

const filtered = computed(() => {
    let list = playbooks.value ?? [];
    if (activeCategory.value !== 'all') list = list.filter(p => p.category === activeCategory.value);
    if (filterText.value.trim()) {
        const q = filterText.value.toLowerCase();
        list = list.filter(p => p.title.toLowerCase().includes(q) || p.description?.toLowerCase().includes(q));
    }
    return list;
});

function filteredByColumn(status: PlaybookStatus) {
    return filtered.value.filter(p => p.status === status);
}

async function submitPlaybook() {
    formError.value = '';
    if (!newPlaybook.title.trim()) { formError.value = 'Title is required'; return; }
    submitting.value = true;
    try {
        await $fetch('/api/playbooks', { method: 'POST', body: { ...newPlaybook } });
        await refresh();
        showForm.value = false;
        Object.assign(newPlaybook, { title: '', description: '', category: 'delivery', difficulty: 'intermediate', status: 'planned' });
    } catch (e: unknown) {
        formError.value = (e as { data?: { message?: string } })?.data?.message ?? 'Failed to create playbook';
    } finally {
        submitting.value = false;
    }
}

function categoryColor(c: string) {
    const map: Record<string, 'primary' | 'warning' | 'error' | 'success'> = {
        delivery: 'primary', observability: 'warning', resilience: 'success', security: 'error',
    };
    return map[c] ?? 'neutral' as any;
}
function difficultyColor(d: string) {
    return d === 'advanced' ? 'error' as const : 'warning' as const;
}
</script>

<style scoped>
.slide-down-enter-active,
.slide-down-leave-active {
    transition: all 0.25s ease;
    overflow: hidden;
}
.slide-down-enter-from,
.slide-down-leave-to {
    max-height: 0;
    opacity: 0;
}
.slide-down-enter-to,
.slide-down-leave-from {
    max-height: 1200px;
    opacity: 1;
}
</style>
