<template>
  <div class="mx-auto flex w-full max-w-3xl flex-col gap-6">
    <NuxtLink to="/resources" class="inline-flex items-center gap-1 text-sm text-muted hover:text-primary">
      <UIcon name="i-heroicons-arrow-left" class="size-4" />
      Back to resources
    </NuxtLink>

    <div v-if="pending" class="space-y-3">
      <USkeleton class="h-8 w-1/2 rounded-lg" />
      <USkeleton class="h-4 w-40 rounded" />
      <USkeleton class="h-32 rounded-2xl" />
    </div>

    <UCard v-else-if="resource" :ui="{ body: 'p-6 sm:p-8' }">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0">
          <h1 class="text-2xl font-bold text-highlighted sm:text-3xl">{{ resource.title }}</h1>
          <p class="mt-2 text-sm text-muted">{{ resource.description }}</p>
        </div>
        <UBadge variant="soft" color="primary" class="capitalize">{{ resource.type }}</UBadge>
      </div>

      <div class="mt-5 flex flex-wrap gap-2">
        <UBadge v-if="resource.track" variant="soft" color="neutral">{{ resource.track }}</UBadge>
        <UBadge v-for="tag in resource.tags || []" :key="tag" variant="soft" color="neutral">{{ tag }}</UBadge>
      </div>

      <USeparator class="my-6" />

      <div class="space-y-2">
        <p class="text-xs font-semibold uppercase tracking-wide text-muted">Resource link</p>
        <a :href="resource.url" target="_blank" rel="noopener noreferrer"
          class="inline-flex items-center gap-2 text-sm text-primary hover:underline break-all">
          <UIcon name="i-heroicons-arrow-top-right-on-square" class="size-4" />
          {{ resource.url }}
        </a>
      </div>
    </UCard>

    <UAlert
      v-else
      color="warning"
      variant="soft"
      title="Resource not found"
      description="This resource may have been removed."
    />
  </div>
</template>

<script setup lang="ts">
import type { Resource } from '~/types/api';

const route = useRoute();
const resourceId = computed(() => String(route.params.id || ''));

const { data: resource, pending } = useFetch<Resource>(() => `/api/resources/${resourceId.value}`);
</script>
