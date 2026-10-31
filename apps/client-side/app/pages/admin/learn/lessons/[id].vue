<template>
  <div class="flex flex-col gap-4 h-full min-h-0">
    <!-- Header -->
    <div class="flex items-center justify-between gap-3 shrink-0">
      <div class="flex items-center gap-3 min-w-0">
        <UButton variant="ghost" color="neutral" size="xs" leading-icon="i-heroicons-arrow-left" @click="$router.back()">
          Back
        </UButton>
        <div v-if="lesson" class="min-w-0">
          <h1 class="text-base font-bold text-highlighted truncate">{{ lesson.title }}</h1>
          <p class="text-xs text-muted">{{ lesson.slug }}</p>
        </div>
        <USkeleton v-else class="h-6 w-48" />
      </div>
      <div class="shrink-0">
        <UButton size="sm" :loading="saving" leading-icon="i-heroicons-check" @click="save">
          Save
        </UButton>
      </div>
    </div>

    <!-- Metadata row -->
    <div v-if="lesson" class="grid grid-cols-2 gap-3 sm:grid-cols-4 shrink-0">
      <UFormField label="Title">
        <UInput v-model="form.title" class="w-full" />
      </UFormField>
      <UFormField label="Slug">
        <UInput v-model="form.slug" class="w-full" />
      </UFormField>
      <UFormField label="Type">
        <USelect v-model="form.type" :items="lessonTypes" class="w-full" />
      </UFormField>
      <UFormField label="Duration (min)">
        <UInput v-model.number="form.durationMinutes" type="number" :min="1" class="w-full" />
      </UFormField>
    </div>

    <!-- Editor -->
    <MarkdownEditor v-model="form.content" class="flex-1 min-h-0" />

    <UAlert v-if="saveError" color="error" variant="soft" :description="saveError" class="shrink-0" />
  </div>
</template>

<script setup lang="ts">
import type { AdminLessonDetail } from '~/types/api';

definePageMeta({ middleware: ['admin'], layout: 'admin' });

const route = useRoute();
const id = route.params.id as string;

const { data: lesson, pending } = useFetch<AdminLessonDetail>(`/api/learn/admin/lessons/${id}`);

const lessonTypes = ['reading', 'lab', 'quiz'];

const form = reactive({
  title: '',
  slug: '',
  type: 'reading',
  durationMinutes: 10,
  content: '',
});

watch(lesson, (val) => {
  if (val) {
    form.title = val.title;
    form.slug = val.slug;
    form.type = val.type;
    form.durationMinutes = val.durationMinutes;
    form.content = val.content;
  }
}, { immediate: true });

const saving = ref(false);
const saveError = ref('');

async function save() {
  saving.value = true;
  saveError.value = '';
  try {
    await $fetch(`/api/learn/admin/lessons/${id}`, {
      method: 'PATCH',
      body: {
        title: form.title,
        slug: form.slug,
        type: form.type,
        durationMinutes: form.durationMinutes,
        content: form.content,
      },
    });
  } catch (e: unknown) {
    const err = e as { data?: { message?: string }; message?: string };
    saveError.value = err.data?.message ?? err.message ?? 'Save failed';
  } finally {
    saving.value = false;
  }
}
</script>
