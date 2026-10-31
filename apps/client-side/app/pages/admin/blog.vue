<template>
  <div class="space-y-6">
    <div class="flex items-center justify-between gap-3">
      <div class="flex items-center gap-3">
        <NuxtLink to="/admin">
          <UButton variant="ghost" color="neutral" size="xs" leading-icon="i-heroicons-arrow-left">Admin</UButton>
        </NuxtLink>
        <div>
          <h1 class="text-xl font-bold text-highlighted">Blog</h1>
          <p class="text-sm text-muted">{{ posts?.length ?? 0 }} posts</p>
        </div>
      </div>
      <UButton size="sm" leading-icon="i-heroicons-plus" @click="openCreate">New Post</UButton>
    </div>

    <UCard v-if="pending" :ui="{ body: 'space-y-2 p-4' }">
      <USkeleton v-for="i in 4" :key="i" class="h-14 rounded-xl" />
    </UCard>

    <UCard v-else-if="posts?.length" :ui="{ body: 'p-0' }">
      <div class="divide-y divide-default">
        <div v-for="post in posts" :key="post.id" class="flex items-center justify-between gap-3 px-5 py-4">
          <div class="min-w-0">
            <p class="truncate text-sm font-semibold text-highlighted">{{ post.title }}</p>
            <p class="mt-0.5 text-xs text-muted">/{{ post.slug }}</p>
          </div>
          <div class="flex items-center gap-1.5 shrink-0">
            <NuxtLink :to="`/blog/${post.slug}`" target="_blank">
              <UButton size="xs" variant="ghost" color="neutral" leading-icon="i-heroicons-arrow-top-right-on-square" />
            </NuxtLink>
            <UButton size="xs" variant="ghost" color="neutral" leading-icon="i-heroicons-pencil-square" @click="openEdit(post)" />
            <UButton size="xs" variant="ghost" color="error" leading-icon="i-heroicons-trash" @click="confirmDelete(post)" />
          </div>
        </div>
      </div>
    </UCard>

    <UAlert v-else color="neutral" variant="soft" title="No blog posts" description="Create your first blog post." />

    <UModal v-model:open="formModal.open" :ui="{ content: 'w-full max-w-4xl' }">
      <template #content>
        <UCard :ui="{ body: 'flex flex-col gap-4 p-5' }">
          <h3 class="font-semibold text-highlighted">{{ formModal.editing ? 'Edit Post' : 'New Post' }}</h3>

          <UFormField label="Title" required>
            <UInput v-model="formModal.title" placeholder="Post title" class="w-full" />
          </UFormField>

          <UFormField label="Content" required class="flex flex-col flex-1 min-h-0">
            <MarkdownEditor v-model="formModal.content" placeholder="Write blog content in Markdown…" min-height="460px" class="flex-1 min-h-0" />
          </UFormField>

          <div class="flex justify-end gap-2">
            <UButton variant="ghost" color="neutral" @click="formModal.open = false">Cancel</UButton>
            <UButton :loading="formModal.saving" @click="savePost">{{ formModal.editing ? 'Save' : 'Create' }}</UButton>
          </div>
        </UCard>
      </template>
    </UModal>

    <UModal v-model:open="deleteModal.open">
      <template #content>
        <UCard :ui="{ body: 'space-y-4 p-5' }">
          <h3 class="font-semibold text-highlighted">Delete Post</h3>
          <p class="text-sm text-muted">Delete <strong class="text-highlighted">{{ deleteModal.title }}</strong> permanently?</p>
          <div class="flex justify-end gap-2">
            <UButton variant="ghost" color="neutral" @click="deleteModal.open = false">Cancel</UButton>
            <UButton color="error" :loading="deleteModal.deleting" @click="performDelete">Delete</UButton>
          </div>
        </UCard>
      </template>
    </UModal>
  </div>
</template>

<script setup lang="ts">
import type { BlogPost } from '~/types/api';

definePageMeta({ middleware: ['admin'], layout: 'admin' });

const { data: posts, pending, refresh } = useFetch<BlogPost[]>('/api/blog');

const formModal = reactive({
  open: false,
  editing: false,
  id: '',
  title: '',
  content: '',
  saving: false,
});

const deleteModal = reactive({ open: false, id: '', title: '', deleting: false });

function openCreate() {
  formModal.editing = false;
  formModal.id = '';
  formModal.title = '';
  formModal.content = '';
  formModal.open = true;
}

function openEdit(post: BlogPost) {
  formModal.editing = true;
  formModal.id = post.id;
  formModal.title = post.title;
  formModal.content = post.content;
  formModal.open = true;
}

async function savePost() {
  formModal.saving = true;
    try {
    const body = {
      title: formModal.title,
      content: formModal.content,
    };

    if (formModal.editing) {
      await $fetch(`/api/blog/admin/posts/${formModal.id}`, { method: 'PATCH', body });
    } else {
      await $fetch('/api/blog/admin/posts', { method: 'POST', body });
    }

    formModal.open = false;
    await refresh();
  } finally {
    formModal.saving = false;
  }
}

function confirmDelete(post: BlogPost) {
  deleteModal.id = post.id;
  deleteModal.title = post.title;
  deleteModal.open = true;
}

async function performDelete() {
  deleteModal.deleting = true;
    try {
    await $fetch(`/api/blog/admin/posts/${deleteModal.id}`, { method: 'DELETE' });
    deleteModal.open = false;
    await refresh();
  } finally {
    deleteModal.deleting = false;
  }
}

</script>
