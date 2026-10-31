<template>
  <div class="space-y-6">
    <!-- Header -->
    <div class="flex items-center gap-3">
      <NuxtLink to="/admin/learn">
        <UButton variant="ghost" color="neutral" size="xs" leading-icon="i-heroicons-arrow-left">
          All Tracks
        </UButton>
      </NuxtLink>
    </div>

    <div v-if="trackPending">
      <USkeleton class="h-8 w-48 mb-2" />
      <USkeleton class="h-4 w-72" />
    </div>

    <template v-else-if="track">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-xl font-bold text-highlighted">{{ track.title }}</h1>
          <p class="text-sm text-muted mt-0.5">{{ track.modules?.length ?? 0 }} modules</p>
        </div>
        <UButton size="sm" leading-icon="i-heroicons-plus" @click="openAddModule()">
          Add Module
        </UButton>
      </div>

      <!-- Modules -->
      <div class="space-y-4">
        <UCard
          v-for="mod in track.modules"
          :key="mod.id"
          :ui="{ body: 'p-0' }"
        >
          <!-- Module header -->
          <div class="flex items-center justify-between gap-3 px-5 py-3 border-b border-default">
            <div class="flex items-center gap-2 min-w-0">
              <UIcon name="i-heroicons-squares-2x2" class="size-4 text-muted shrink-0" />
              <span class="font-semibold text-highlighted truncate">{{ mod.title }}</span>
              <UBadge :label="`#${mod.order}`" variant="outline" color="neutral" size="xs" />
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <UButton
                size="xs"
                variant="ghost"
                color="neutral"
                leading-icon="i-heroicons-pencil-square"
                @click="openEditModule(mod)"
              />
              <UButton
                size="xs"
                variant="ghost"
                color="error"
                leading-icon="i-heroicons-trash"
                @click="confirmDeleteModule(mod)"
              />
              <UButton
                size="xs"
                variant="soft"
                leading-icon="i-heroicons-plus"
                @click="openAddLesson(mod.id)"
              >
                Lesson
              </UButton>
            </div>
          </div>

          <!-- Lessons list -->
          <div v-if="mod.lessons?.length" class="divide-y divide-default">
            <div
              v-for="lesson in mod.lessons"
              :key="lesson.id"
              class="flex items-center justify-between gap-3 px-5 py-2.5"
            >
              <div class="flex items-center gap-3 min-w-0">
                <UIcon :name="lessonTypeIcon(lesson.type)" class="size-4 text-muted shrink-0" />
                <span class="text-sm text-highlighted truncate">{{ lesson.title }}</span>
                <UBadge :label="lesson.type" variant="soft" color="primary" size="xs" class="capitalize" />
                <span class="text-xs text-muted">{{ lesson.durationMinutes }}m</span>
              </div>
              <div class="flex items-center gap-1.5 shrink-0">
                <NuxtLink :to="`/admin/learn/lessons/${lesson.id}`">
                  <UButton size="xs" variant="ghost" color="neutral" leading-icon="i-heroicons-pencil-square" />
                </NuxtLink>
                <UButton
                  size="xs"
                  variant="ghost"
                  color="error"
                  leading-icon="i-heroicons-trash"
                  @click="confirmDeleteLesson(lesson)"
                />
              </div>
            </div>
          </div>
          <div v-else class="px-5 py-4 text-sm text-muted text-center">
            No lessons yet &mdash; add one above.
          </div>
        </UCard>
      </div>
    </template>

    <!-- Module modal -->
    <UModal v-model:open="moduleModal.open">
      <template #content>
        <UCard :ui="{ body: 'space-y-4 p-5' }">
          <h3 class="font-semibold text-highlighted">
            {{ moduleModal.editing ? 'Edit Module' : 'New Module' }}
          </h3>
          <UFormField label="Title" required>
            <UInput v-model="moduleModal.title" placeholder="Module title" class="w-full" />
          </UFormField>
          <UFormField label="Order">
            <UInput v-model.number="moduleModal.order" type="number" :min="0" class="w-full" />
          </UFormField>
          <div class="flex justify-end gap-2 pt-2">
            <UButton variant="ghost" color="neutral" @click="moduleModal.open = false">Cancel</UButton>
            <UButton :loading="moduleModal.saving" @click="saveModule">
              {{ moduleModal.editing ? 'Save' : 'Create' }}
            </UButton>
          </div>
        </UCard>
      </template>
    </UModal>

    <!-- Add Lesson modal -->
    <UModal v-model:open="lessonModal.open">
      <template #content>
        <UCard :ui="{ body: 'space-y-4 p-5' }">
          <h3 class="font-semibold text-highlighted">Add Lesson</h3>
          <UFormField label="Title" required>
            <UInput v-model="lessonModal.title" placeholder="Lesson title" class="w-full" />
          </UFormField>
          <UFormField label="Slug" required>
            <UInput v-model="lessonModal.slug" placeholder="lesson-slug" class="w-full" />
          </UFormField>
          <UFormField label="Type">
            <USelect
              v-model="lessonModal.type"
              :items="lessonTypes"
              class="w-full"
            />
          </UFormField>
          <div class="grid grid-cols-2 gap-3">
            <UFormField label="Duration (min)">
              <UInput v-model.number="lessonModal.durationMinutes" type="number" :min="1" class="w-full" />
            </UFormField>
            <UFormField label="Order">
              <UInput v-model.number="lessonModal.order" type="number" :min="0" class="w-full" />
            </UFormField>
          </div>
          <div class="flex justify-end gap-2 pt-2">
            <UButton variant="ghost" color="neutral" @click="lessonModal.open = false">Cancel</UButton>
            <UButton :loading="lessonModal.saving" @click="saveLesson">Create</UButton>
          </div>
        </UCard>
      </template>
    </UModal>

    <!-- Delete confirmation modal -->
    <UModal v-model:open="deleteModal.open">
      <template #content>
        <UCard :ui="{ body: 'space-y-4 p-5' }">
          <h3 class="font-semibold text-highlighted">Confirm Delete</h3>
          <p class="text-sm text-muted">
            Delete <strong class="text-highlighted">{{ deleteModal.name }}</strong>?
            This action cannot be undone.
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
import type { TrackDetail, TrackModule, LessonSummary } from '~/types/api';

definePageMeta({ middleware: ['admin'], layout: 'admin' });

const route = useRoute();
const slug = route.params.track as string;

const { data: track, pending: trackPending, refresh } = useFetch<TrackDetail>(`/api/learn/tracks/${slug}`);

const lessonTypes = ['reading', 'lab', 'quiz'];

function lessonTypeIcon(type: string) {
  if (type === 'lab') return 'i-heroicons-command-line';
  if (type === 'quiz') return 'i-heroicons-question-mark-circle';
  return 'i-heroicons-book-open';
}

// ── Module modal ──────────────────────────────────────────────────────────────
const moduleModal = reactive({
  open: false,
  editing: false,
  id: '',
  title: '',
  order: 0,
  saving: false,
});

function openAddModule() {
  moduleModal.editing = false;
  moduleModal.id = '';
  moduleModal.title = '';
  moduleModal.order = (track.value?.modules?.length ?? 0) + 1;
  moduleModal.open = true;
}

function openEditModule(mod: TrackModule) {
  moduleModal.editing = true;
  moduleModal.id = mod.id;
  moduleModal.title = mod.title;
  moduleModal.order = mod.order;
  moduleModal.open = true;
}

async function saveModule() {
  moduleModal.saving = true;
  try {
    if (moduleModal.editing) {
      await $fetch(`/api/learn/admin/modules/${moduleModal.id}`, {
        method: 'PATCH',
        body: { title: moduleModal.title, order: moduleModal.order },
      });
    } else {
      await $fetch('/api/learn/admin/modules', {
        method: 'POST',
        body: { courseId: track.value!.id, title: moduleModal.title, order: moduleModal.order },
      });
    }
    moduleModal.open = false;
    await refresh();
  } finally {
    moduleModal.saving = false;
  }
}

// ── Lesson modal ──────────────────────────────────────────────────────────────
const lessonModal = reactive({
  open: false,
  moduleId: '',
  title: '',
  slug: '',
  type: 'reading',
  durationMinutes: 10,
  order: 1,
  saving: false,
});

function openAddLesson(moduleId: string) {
  lessonModal.moduleId = moduleId;
  lessonModal.title = '';
  lessonModal.slug = '';
  lessonModal.type = 'reading';
  lessonModal.durationMinutes = 10;
  lessonModal.order = 1;
  lessonModal.open = true;
}

async function saveLesson() {
  lessonModal.saving = true;
  try {
    const created = await $fetch<{ id: string }>('/api/learn/admin/lessons', {
      method: 'POST',
      body: {
        moduleId: lessonModal.moduleId,
        title: lessonModal.title,
        slug: lessonModal.slug,
        type: lessonModal.type,
        content: '',
        durationMinutes: lessonModal.durationMinutes,
        order: lessonModal.order,
      },
    });
    lessonModal.open = false;
    await refresh();
    await navigateTo(`/admin/learn/lessons/${created.id}`);
  } finally {
    lessonModal.saving = false;
  }
}

// ── Delete modal ──────────────────────────────────────────────────────────────
const deleteModal = reactive({
  open: false,
  type: '' as 'module' | 'lesson',
  id: '',
  name: '',
  deleting: false,
});

function confirmDeleteModule(mod: TrackModule) {
  deleteModal.type = 'module';
  deleteModal.id = mod.id;
  deleteModal.name = mod.title;
  deleteModal.open = true;
}

function confirmDeleteLesson(lesson: LessonSummary) {
  deleteModal.type = 'lesson';
  deleteModal.id = lesson.id;
  deleteModal.name = lesson.title;
  deleteModal.open = true;
}

async function performDelete() {
  deleteModal.deleting = true;
  try {
    const path = deleteModal.type === 'module'
      ? `/api/learn/admin/modules/${deleteModal.id}`
      : `/api/learn/admin/lessons/${deleteModal.id}`;
    await $fetch(path, { method: 'DELETE' });
    deleteModal.open = false;
    await refresh();
  } finally {
    deleteModal.deleting = false;
  }
}
</script>
