<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-bold text-highlighted">Content Management</h1>
      <p class="text-sm text-muted mt-0.5">Manage all content across the platform</p>
    </div>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <NuxtLink
        v-for="section in sections"
        :key="section.to"
        :to="section.to"
        class="group flex flex-col gap-4 rounded-xl border border-default bg-elevated/40 p-6 transition-all hover:bg-elevated hover:shadow-md"
      >
        <div class="flex items-center justify-between">
          <div
            class="flex size-11 items-center justify-center rounded-xl"
            :style="{ background: section.color + '22' }"
          >
            <UIcon :name="section.icon" class="size-6" :style="{ color: section.color }" />
          </div>
          <UIcon name="i-heroicons-chevron-right" class="size-4 text-muted opacity-0 group-hover:opacity-100 transition-opacity" />
        </div>
        <div>
          <p class="font-semibold text-highlighted group-hover:text-primary transition-colors">{{ section.title }}</p>
          <p class="mt-1 text-sm text-muted">{{ section.description }}</p>
        </div>
      </NuxtLink>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ middleware: ['admin'], layout: 'admin' });

const sections = [
  {
    title: 'Learning Content',
    description: 'Manage tracks, modules, and lessons',
    to: '/admin/learn',
    icon: 'i-heroicons-academic-cap',
    color: '#14b8a6',
  },
  {
    title: 'Playbooks',
    description: 'Create, edit, and remove playbooks',
    to: '/admin/playbooks',
    icon: 'i-heroicons-clipboard-document-list',
    color: '#6366f1',
  },
  {
    title: 'Resources',
    description: 'Curate links, tools, and references',
    to: '/admin/resources',
    icon: 'i-heroicons-link',
    color: '#f59e0b',
  },
];
</script>
