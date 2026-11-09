<!--
  Public marketing chrome: the floating pill nav and the footer.

  Both live here rather than in each page so `/` and `/about` cannot drift apart
  — previously the whole header was copy-pasted between them.
-->
<template>
    <div class="min-h-screen bg-default">
        <header class="sticky top-0 z-50 px-4 py-4">
            <nav
                class="mx-auto flex w-fit max-w-full items-center gap-0.5 overflow-x-auto rounded-full border border-default bg-elevated/70 p-1 backdrop-blur">
                <NuxtLink v-for="link in navLinks" :key="link.to" :to="link.to"
                    class="shrink-0 rounded-full px-3.5 py-1.5 text-sm text-muted transition-colors hover:text-highlighted"
                    active-class="bg-default text-highlighted shadow-sm">
                    {{ link.label }}
                </NuxtLink>
                <UColorModeButton size="sm" variant="ghost" color="neutral" class="ml-0.5 shrink-0 rounded-full" />
            </nav>
        </header>

        <main class="mx-auto w-full max-w-3xl px-4 sm:px-6">
            <slot />
        </main>

        <footer class="border-t border-default">
            <div
                class="mx-auto flex w-full max-w-3xl flex-col items-center justify-between gap-4 px-4 py-8 sm:flex-row sm:px-6">
                <p class="text-xs text-dimmed">
                    DevOps Learning Hub &bull; &copy; {{ new Date().getFullYear() }} &bull; Built once by Jenkins, scanned by Trivy + SonarQube, promoted dev → uat → prod by Argo CD
                </p>
                <div class="flex items-center gap-4">
                    <ULink v-for="s in socialLinks" :key="s.label" :to="s.to" target="_blank" :aria-label="s.label"
                        class="text-dimmed transition-colors hover:text-highlighted">
                        <UIcon :name="s.icon" class="size-4" />
                    </ULink>
                </div>
            </div>
        </footer>
    </div>
</template>

<script setup lang="ts">
const { navLinks, socialLinks } = useSiteNav();
</script>
