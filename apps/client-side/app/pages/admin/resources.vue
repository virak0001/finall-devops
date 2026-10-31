<template>
  <div class="space-y-6">
    <!-- Header -->
    <div class="flex items-center justify-between gap-3">
      <div class="flex items-center gap-3">
        <NuxtLink to="/admin">
          <UButton variant="ghost" color="neutral" size="xs" leading-icon="i-heroicons-arrow-left">Admin</UButton>
        </NuxtLink>
        <div>
          <h1 class="text-xl font-bold text-highlighted">Resources</h1>
          <p class="text-sm text-muted">{{ resources?.length ?? 0 }} total</p>
        </div>
      </div>
      <UButton size="sm" leading-icon="i-heroicons-plus" @click="openCreate">New Resource</UButton>
    </div>

    <!-- Filter bar -->
    <div class="flex flex-wrap items-center gap-3">
      <UInput v-model="search" placeholder="Search…" leading-icon="i-heroicons-magnifying-glass" size="sm" :ui="{ root: 'w-48' }" />
      <div class="flex gap-1.5">
        <UButton
          v-for="t in ['all', ...resourceTypes]"
          :key="t"
          size="xs"
          :variant="activeType === t ? 'solid' : 'soft'"
          :color="activeType === t ? 'primary' : 'neutral'"
          class="capitalize"
          @click="activeType = t"
        >{{ t }}</UButton>
      </div>
    </div>

    <!-- Skeleton -->
    <div v-if="pending" class="space-y-2">
      <USkeleton v-for="i in 6" :key="i" class="h-14 rounded-xl" />
    </div>

    <!-- Table -->
    <UCard v-else-if="filtered.length" :ui="{ body: 'p-0' }">
      <div class="divide-y divide-default">
        <div
          v-for="r in filtered"
          :key="r.id"
          class="flex items-center justify-between gap-3 px-5 py-3"
        >
          <div class="flex items-center gap-4 min-w-0">
            <UBadge :label="r.type" variant="soft" color="primary" size="xs" class="capitalize shrink-0" />
            <span class="font-medium text-highlighted text-sm truncate">{{ r.title }}</span>
            <UBadge v-if="r.track" :label="r.track" variant="outline" color="neutral" size="xs" class="shrink-0 hidden sm:inline-flex" />
          </div>
          <div class="flex items-center gap-1.5 shrink-0">
            <a :href="r.url" target="_blank" rel="noopener noreferrer">
              <UButton size="xs" variant="ghost" color="neutral" leading-icon="i-heroicons-arrow-top-right-on-square" />
            </a>
            <UButton size="xs" variant="ghost" color="neutral" leading-icon="i-heroicons-pencil-square" @click="openEdit(r)" />
            <UButton size="xs" variant="ghost" color="error" leading-icon="i-heroicons-trash" @click="confirmDelete(r)" />
          </div>
        </div>
      </div>
    </UCard>

    <p v-else class="text-sm text-muted text-center py-10">No resources found.</p>

    <!-- Create / Edit modal -->
    <UModal v-model:open="formModal.open">
      <template #content>
        <UCard :ui="{ body: 'space-y-4 p-5' }">
          <h3 class="font-semibold text-highlighted">{{ formModal.editing ? 'Edit Resource' : 'New Resource' }}</h3>

          <UFormField label="Title" required>
            <UInput v-model="formModal.title" placeholder="Resource title" class="w-full" />
          </UFormField>
          <UFormField label="URL" required>
            <UInput v-model="formModal.url" placeholder="https://..." class="w-full" />
          </UFormField>
          <UFormField label="Description" required>
            <UTextarea v-model="formModal.description" :rows="2" placeholder="Brief description" class="w-full" />
          </UFormField>
          <div class="grid grid-cols-2 gap-3">
            <UFormField label="Type">
              <USelect v-model="formModal.type" :items="resourceTypes" class="w-full" />
            </UFormField>
            <UFormField label="Track">
              <USelect v-model="formModal.track" :items="trackOptions" class="w-full" />
            </UFormField>
          </div>
          <UFormField label="Tags (comma-separated)">
            <UInput v-model="formModal.tagsRaw" placeholder="docker, ci-cd, security" class="w-full" />
          </UFormField>

          <div class="flex justify-end gap-2 pt-2">
            <UButton variant="ghost" color="neutral" @click="formModal.open = false">Cancel</UButton>
            <UButton :loading="formModal.saving" @click="saveResource">
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
          <h3 class="font-semibold text-highlighted">Delete Resource</h3>
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
import type { Resource } from '~/types/api';

definePageMeta({ middleware: ['admin'], layout: 'admin' });

const resourceTypes = ['tool', 'article', 'cheatsheet', 'video', 'reference'];
const trackOptions = ['', 'foundation', 'ci-cd', 'security', 'observability', 'resilience', 'cloud-gitops'];

const search = ref('');
const activeType = ref('all');

const { data: resources, pending, refresh } = useFetch<Resource[]>('/api/resources');

const filtered = computed(() => {
  let list = resources.value ?? [];
  if (activeType.value !== 'all') list = list.filter((r) => r.type === activeType.value);
  if (search.value) {
    const q = search.value.toLowerCase();
    list = list.filter((r) => r.title.toLowerCase().includes(q) || r.description.toLowerCase().includes(q));
  }
  return list;
});

// ── Form modal ────────────────────────────────────────────────────────────────

const formModal = reactive({
  open: false,
  editing: false,
  id: '',
  title: '',
  url: '',
  description: '',
  type: 'reference' as string,
  track: '',
  tagsRaw: '',
  saving: false,
});

function openCreate() {
  formModal.editing = false;
  formModal.id = '';
  formModal.title = '';
  formModal.url = '';
  formModal.description = '';
  formModal.type = 'reference';
  formModal.track = '';
  formModal.tagsRaw = '';
  formModal.open = true;
}

function openEdit(r: Resource) {
  formModal.editing = true;
  formModal.id = r.id;
  formModal.title = r.title;
  formModal.url = r.url;
  formModal.description = r.description;
  formModal.type = r.type;
  formModal.track = r.track ?? '';
  formModal.tagsRaw = (r.tags ?? []).join(', ');
  formModal.open = true;
}

async function saveResource() {
  formModal.saving = true;
  try {
    const body = {
      title: formModal.title,
      url: formModal.url,
      description: formModal.description,
      type: formModal.type,
      track: formModal.track,
      tags: formModal.tagsRaw.split(',').map((t) => t.trim()).filter(Boolean),
    };
    if (formModal.editing) {
      await $fetch(`/api/resources/${formModal.id}`, { method: 'PATCH', body });
    } else {
      await $fetch('/api/resources', { method: 'POST', body });
    }
    formModal.open = false;
    await refresh();
  } finally {
    formModal.saving = false;
  }
}

// ── Delete modal ──────────────────────────────────────────────────────────────

const deleteModal = reactive({ open: false, id: '', title: '', deleting: false });

function confirmDelete(r: Resource) {
  deleteModal.id = r.id;
  deleteModal.title = r.title;
  deleteModal.open = true;
}

async function performDelete() {
  deleteModal.deleting = true;
  try {
    await $fetch(`/api/resources/${deleteModal.id}`, { method: 'DELETE' });
    deleteModal.open = false;
    await refresh();
  } finally {
    deleteModal.deleting = false;
  }
}
</script>
