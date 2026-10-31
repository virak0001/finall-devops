<script setup lang="ts">
const config = useRuntimeConfig();
</script>

<template>
    <div
      v-if="config.public.isStaging"
      class="pointer-events-none fixed top-0 right-0 z-50 bg-red-500 px-2.5 py-1 text-xs font-semibold uppercase tracking-wide text-white shadow-lg ring-1 ring-amber-600/50"
      aria-hidden="true"
    >
      Staging
    </div>
  <UApp>
    <NuxtRouteAnnouncer />
    <NuxtLoadingIndicator color="rgb(var(--ui-primary))" />
    <NuxtLayout>
      <NuxtPage />
    </NuxtLayout>
  </UApp>
</template>
