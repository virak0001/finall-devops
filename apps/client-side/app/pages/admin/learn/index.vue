<template>
  <div class="space-y-6">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-xl font-bold text-highlighted">Learning Tracks</h1>
        <p class="text-sm text-muted mt-0.5">Manage tracks, modules, and lessons</p>
      </div>
      <UButton size="sm" leading-icon="i-heroicons-plus" @click="openCreate">New Track</UButton>
    </div>

    <div v-if="pending" class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <USkeleton v-for="i in 6" :key="i" class="h-36 rounded-xl" />
    </div>

    <div v-else-if="tracks" class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="track in tracks"
        :key="track.id"
        class="group relative flex flex-col gap-3 rounded-xl border border-default bg-elevated/40 p-5 transition-all hover:bg-elevated hover:shadow-md cursor-pointer"
        @click="navigateTo(`/admin/learn/${track.trackSlug}`)"
      >
        <!-- Action buttons -->
        <div class="absolute top-3 right-3 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity z-10">
          <UButton size="xs" variant="ghost" color="neutral" icon="i-heroicons-pencil-square" @click.stop="openEdit(track)" />
          <UButton size="xs" variant="ghost" color="error" icon="i-heroicons-trash" @click.stop="confirmDelete(track)" />
        </div>

        <div class="flex items-start justify-between gap-3 pr-16">
          <div class="flex size-10 shrink-0 items-center justify-center rounded-xl" :style="{ background: track.color + '22' }">
            <UIcon :name="track.icon || 'i-heroicons-academic-cap'" class="size-5" :style="{ color: track.color }" />
          </div>
          <UBadge :label="track.level" variant="soft" color="neutral" size="sm" class="capitalize" />
        </div>

        <div>
          <p class="font-semibold text-highlighted group-hover:text-primary transition-colors">{{ track.title }}</p>
          <p class="mt-1 text-xs text-muted line-clamp-2">{{ track.description }}</p>
        </div>

        <div class="flex items-center gap-3 text-xs text-muted">
          <span class="flex items-center gap-1">
            <UIcon name="i-heroicons-squares-2x2" class="size-3.5" />
            {{ track.moduleCount }} modules
          </span>
          <span class="flex items-center gap-1">
            <UIcon name="i-heroicons-document-text" class="size-3.5" />
            {{ track.lessonCount }} lessons
          </span>
        </div>
      </div>
    </div>

    <UAlert v-else-if="error" color="error" variant="soft" :description="error.message" />

    <!-- Create / Edit modal -->
    <UModal v-model:open="formModal.open">
      <template #content>
        <UCard :ui="{ body: 'space-y-4 p-5' }">
          <h3 class="font-semibold text-highlighted">{{ formModal.editing ? 'Edit Track' : 'New Track' }}</h3>

          <div class="grid grid-cols-2 gap-3">
            <UFormField label="Slug" required class="col-span-2">
              <UInput v-model="formModal.trackSlug" placeholder="e.g. cloud-gitops" class="w-full" />
            </UFormField>
            <UFormField label="Title" required class="col-span-2">
              <UInput v-model="formModal.title" placeholder="Track title" class="w-full" />
            </UFormField>
            <UFormField label="Description" required class="col-span-2">
              <UTextarea v-model="formModal.description" :rows="2" placeholder="Short description" class="w-full" />
            </UFormField>
            <UFormField label="Level">
              <USelect v-model="formModal.level" :items="levels" class="w-full" />
            </UFormField>
            <UFormField label="Order">
              <UInput v-model.number="formModal.order" type="number" :min="0" class="w-full" />
            </UFormField>
            <UFormField label="Color (hex)">
              <UInput v-model="formModal.color" placeholder="#2ec4b6" class="w-full" />
            </UFormField>
            <UFormField label="Icon (heroicons name)">
              <UInput v-model="formModal.icon" placeholder="i-heroicons-academic-cap" class="w-full" />
            </UFormField>
          </div>

          <div class="flex justify-end gap-2 pt-2">
            <UButton variant="ghost" color="neutral" @click="formModal.open = false">Cancel</UButton>
            <UButton :loading="formModal.saving" @click="saveTrack">
              {{ formModal.editing ? 'Save' : 'Create' }}
            </UButton>
          </div>
        </UCard>
      </template>
    </UModal>

    <!-- Delete confirmation modal -->
    <UModal v-model:open="deleteModal.open">
      <template #content>
        <UCard :ui="{ body: 'space-y-4 p-5' }">
          <h3 class="font-semibold text-highlighted">Delete Track</h3>
          <p class="text-sm text-muted">
            Delete <strong class="text-highlighted">{{ deleteModal.title }}</strong>? All modules and lessons in this track will also be deleted. This cannot be undone.
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
import type { Track } from '~/types/api';
import type { DifficultyLevel } from '~/types/api';

definePageMeta({ middleware: ['admin'], layout: 'admin' });

interface TrackWithCounts extends Track {
  moduleCount: number;
  lessonCount: number;
}

const { data: tracks, pending, error, refresh } = useFetch<TrackWithCounts[]>('/api/learn/tracks');

const levels: DifficultyLevel[] = ['beginner', 'intermediate', 'advanced'];

// ── Form modal ─────────────────────────────────────────────────────────────────
const formModal = reactive({
  open: false,
  editing: false,
  id: '',
  trackSlug: '',
  title: '',
  description: '',
  level: 'beginner' as DifficultyLevel,
  color: '#2ec4b6',
  icon: 'i-heroicons-academic-cap',
  order: 0,
  saving: false,
});

function openCreate() {
  formModal.editing = false;
  formModal.id = '';
  formModal.trackSlug = '';
  formModal.title = '';
  formModal.description = '';
  formModal.level = 'beginner';
  formModal.color = '#2ec4b6';
  formModal.icon = 'i-heroicons-academic-cap';
  formModal.order = (tracks.value?.length ?? 0) + 1;
  formModal.open = true;
}

function openEdit(track: TrackWithCounts) {
  formModal.editing = true;
  formModal.id = track.id;
  formModal.trackSlug = track.trackSlug;
  formModal.title = track.title;
  formModal.description = track.description;
  formModal.level = track.level;
  formModal.color = track.color;
  formModal.icon = track.icon;
  formModal.order = track.order;
  formModal.open = true;
}

async function saveTrack() {
  formModal.saving = true;
  try {
    const body = {
      trackSlug: formModal.trackSlug,
      title: formModal.title,
      description: formModal.description,
      level: formModal.level,
      color: formModal.color,
      icon: formModal.icon,
      order: formModal.order,
    };
    if (formModal.editing) {
      await $fetch(`/api/learn/admin/tracks/${formModal.id}`, { method: 'PATCH', body });
    } else {
      await $fetch('/api/learn/admin/tracks', { method: 'POST', body });
    }
    formModal.open = false;
    await refresh();
  } finally {
    formModal.saving = false;
  }
}

// ── Delete modal ───────────────────────────────────────────────────────────────
const deleteModal = reactive({
  open: false,
  id: '',
  title: '',
  deleting: false,
});

function confirmDelete(track: TrackWithCounts) {
  deleteModal.id = track.id;
  deleteModal.title = track.title;
  deleteModal.open = true;
}

async function performDelete() {
  deleteModal.deleting = true;
  try {
    await $fetch(`/api/learn/admin/tracks/${deleteModal.id}`, { method: 'DELETE' });
    deleteModal.open = false;
    await refresh();
  } finally {
    deleteModal.deleting = false;
  }
}
</script>
