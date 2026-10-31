<template>
    <div class="space-y-6">
        <!-- Header -->
        <div class="flex items-center justify-between gap-3">
            <div class="flex items-center gap-3">
                <NuxtLink to="/admin">
                    <UButton variant="ghost" color="neutral" size="xs" leading-icon="i-heroicons-arrow-left">Admin
                    </UButton>
                </NuxtLink>
                <div>
                    <h1 class="text-xl font-bold text-highlighted">Playbooks</h1>
                    <p class="text-sm text-muted">{{ playbooks?.length ?? 0 }} total</p>
                </div>
            </div>
            <UButton size="sm" leading-icon="i-heroicons-plus" @click="openCreate">New Playbook</UButton>
        </div>

        <!-- Filter bar -->
        <div class="flex flex-wrap items-center gap-3">
            <UInput v-model="search" placeholder="Search…" leading-icon="i-heroicons-magnifying-glass" size="sm"
                :ui="{ root: 'w-48' }" />
            <div class="flex gap-1.5">
                <UButton v-for="cat in ['all', ...categories]" :key="cat" size="xs"
                    :variant="activeCategory === cat ? 'solid' : 'soft'"
                    :color="activeCategory === cat ? 'primary' : 'neutral'" class="capitalize"
                    @click="activeCategory = cat">{{ cat }}</UButton>
            </div>
        </div>

        <!-- Skeleton -->
        <div v-if="pending" class="space-y-2">
            <USkeleton v-for="i in 5" :key="i" class="h-14 rounded-xl" />
        </div>

        <!-- Table -->
        <UCard v-else-if="filtered.length" :ui="{ body: 'p-0' }">
            <div class="divide-y divide-default">
                <div v-for="pb in filtered" :key="pb.id" class="flex items-center justify-between gap-3 px-5 py-3">
                    <div class="flex items-center gap-4 min-w-0">
                        <UBadge :label="pb.category" variant="soft" color="primary" size="xs"
                            class="capitalize shrink-0" />
                        <span class="font-medium text-highlighted text-sm truncate">{{ pb.title }}</span>
                        <UBadge :label="pb.status" variant="outline" :color="statusColor(pb.status)" size="xs"
                            class="capitalize shrink-0" />
                        <UBadge :label="pb.difficulty" variant="soft" color="neutral" size="xs"
                            class="capitalize shrink-0 hidden sm:inline-flex" />
                    </div>
                    <div class="flex items-center gap-1.5 shrink-0">
                        <UButton size="xs" variant="ghost" color="neutral" leading-icon="i-heroicons-pencil-square"
                            @click="openEdit(pb)" />
                        <UButton size="xs" variant="ghost" color="error" leading-icon="i-heroicons-trash"
                            @click="confirmDelete(pb)" />
                    </div>
                </div>
            </div>
        </UCard>

        <p v-else class="text-sm text-muted text-center py-10">No playbooks found.</p>

        <!-- Create / Edit modal -->
        <UModal v-model:open="formModal.open">
            <template #content>
                <UCard :ui="{ body: 'space-y-4 p-5' }">
                    <h3 class="font-semibold text-highlighted">{{ formModal.editing ? 'Edit Playbook' : 'New Playbook'
                    }}</h3>

                    <UFormField label="Title" required>
                        <UInput v-model="formModal.title" placeholder="e.g. Zero-downtime deployment" class="w-full" />
                    </UFormField>
                    <UFormField label="Description" required>
                        <UTextarea v-model="formModal.description" :rows="3"
                            placeholder="What does this playbook cover?" class="w-full" />
                    </UFormField>
                    <div class="grid grid-cols-3 gap-3">
                        <UFormField label="Category">
                            <USelect v-model="formModal.category" :items="categories" class="w-full" />
                        </UFormField>
                        <UFormField label="Difficulty">
                            <USelect v-model="formModal.difficulty" :items="difficulties" class="w-full" />
                        </UFormField>
                        <UFormField label="Status">
                            <USelect v-model="formModal.status" :items="statuses" class="w-full" />
                        </UFormField>
                    </div>

                    <div class="flex justify-end gap-2 pt-2">
                        <UButton variant="ghost" color="neutral" @click="formModal.open = false">Cancel</UButton>
                        <UButton :loading="formModal.saving" @click="savePlaybook">
                            {{ formModal.editing ? 'Save' : 'Create' }}
                        </UButton>
                    </div>
                </UCard>
            </template>
        </UModal>

        <!-- Delete modal -->
        <UModal v-model:open="deleteModal.open">
            <template #content>
                <UCard :ui="{ body: 'space-y-4 p-5' }">
                    <h3 class="font-semibold text-highlighted">Delete Playbook</h3>
                    <p class="text-sm text-muted">
                        Permanently delete <strong class="text-highlighted">{{ deleteModal.title }}</strong>?
                    </p>
                    <div class="flex justify-end gap-2 pt-2">
                        <UButton variant="ghost" color="neutral" @click="deleteModal.open = false">Cancel</UButton>
                        <UButton color="error" :loading="deleteModal.deleting" @click="performDelete">Delete</UButton>
                    </div>
                </UCard>
            </template>
        </UModal>
    </div>
</template>

<script setup lang="ts">
import type { Playbook } from '~/types/api';

definePageMeta({ middleware: ['admin'], layout: 'admin' });

const categories = ['delivery', 'observability', 'resilience', 'security'];
const difficulties = ['intermediate', 'advanced'];
const statuses = ['planned', 'practicing', 'validated'];

const search = ref('');
const activeCategory = ref('all');

const { data: playbooks, pending, refresh } = useFetch<Playbook[]>('/api/playbooks');

const filtered = computed(() => {
    let list = playbooks.value ?? [];
    if (activeCategory.value !== 'all') list = list.filter((p) => p.category === activeCategory.value);
    if (search.value) {
        const q = search.value.toLowerCase();
        list = list.filter((p) => p.title.toLowerCase().includes(q) || p.description.toLowerCase().includes(q));
    }
    return list;
});

function statusColor(status: string): 'success' | 'warning' | 'neutral' {
    if (status === 'validated') return 'success';
    if (status === 'practicing') return 'warning';
    return 'neutral';
}

// ── Form modal ────────────────────────────────────────────────────────────────

const formModal = reactive({
    open: false,
    editing: false,
    id: '',
    title: '',
    description: '',
    category: 'delivery' as string,
    difficulty: 'intermediate' as string,
    status: 'planned' as string,
    saving: false,
});

function openCreate() {
    formModal.editing = false;
    formModal.id = '';
    formModal.title = '';
    formModal.description = '';
    formModal.category = 'delivery';
    formModal.difficulty = 'intermediate';
    formModal.status = 'planned';
    formModal.open = true;
}

function openEdit(pb: Playbook) {
    formModal.editing = true;
    formModal.id = pb.id;
    formModal.title = pb.title;
    formModal.description = pb.description;
    formModal.category = pb.category;
    formModal.difficulty = pb.difficulty;
    formModal.status = pb.status;
    formModal.open = true;
}

async function savePlaybook() {
    formModal.saving = true;
    try {
        const body = {
            title: formModal.title,
            description: formModal.description,
            category: formModal.category,
            difficulty: formModal.difficulty,
            status: formModal.status,
        };
        if (formModal.editing) {
            await $fetch(`/api/playbooks/${formModal.id}`, { method: 'PATCH', body });
        } else {
            await $fetch('/api/playbooks', { method: 'POST', body });
        }
        formModal.open = false;
        await refresh();
    } finally {
        formModal.saving = false;
    }
}

// ── Delete modal ──────────────────────────────────────────────────────────────

const deleteModal = reactive({ open: false, id: '', title: '', deleting: false });

function confirmDelete(pb: Playbook) {
    deleteModal.id = pb.id;
    deleteModal.title = pb.title;
    deleteModal.open = true;
}

async function performDelete() {
    deleteModal.deleting = true;
    try {
        await $fetch(`/api/playbooks/${deleteModal.id}`, { method: 'DELETE' });
        deleteModal.open = false;
        await refresh();
    } finally {
        deleteModal.deleting = false;
    }
}
</script>
