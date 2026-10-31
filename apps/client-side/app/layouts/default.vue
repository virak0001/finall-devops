<template>
    <UDashboardGroup>
        <UDashboardSidebar collapsible
            :ui="{ body: 'flex flex-col gap-1 p-2', footer: 'border-t border-default px-2 py-3' }">
            <template #header>
                <NuxtLink to="/dashboard" class="flex items-center gap-3 px-2 py-1 min-w-0">
                    <div
                        class="flex size-9 items-center justify-center rounded-xl bg-linear-to-br from-teal-500 to-amber-400 shadow-sm shrink-0">
                        <UIcon name="i-heroicons-cog-6-tooth" class="size-4 text-white" />
                    </div>
                    <div class="min-w-0">
                        <p class="truncate text-sm font-semibold text-highlighted">{{ appName }}</p>
                        <p class="truncate text-xs text-muted">Learning workspace</p>
                    </div>
                </NuxtLink>
            </template>

            <UNavigationMenu orientation="vertical" :items="navItems" content-orientation="vertical"
                :ui="{ root: 'w-full', link: 'rounded-xl px-3 py-2.5' }" />

            <USeparator class="my-2" />

            <template #footer>
                <div class="h-1" />
            </template>
        </UDashboardSidebar>

        <UDashboardPanel grow>
            <UDashboardNavbar title="Dashboard" :toggle="true" toggle-side="left" :ui="{ root: 'border-0' }">
                <template #left>
                    <div class="flex flex-col">
                        <span class="text-sm font-semibold text-highlighted">{{ currentTitle }}</span>
                        <span class="text-xs text-muted">Structured learning and practice</span>
                    </div>
                </template>

                <template #right>
                    <div class="flex items-center gap-2">
                        <NuxtLink v-if="isAdmin" to="/admin"
                            class="hidden sm:flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium text-error hover:bg-error/10 transition-colors">
                            <UIcon name="i-heroicons-cog-8-tooth" class="size-3.5" />
                            Admin
                        </NuxtLink>

                        <NuxtLink to="/profile"
                            class="flex items-center gap-2.5 rounded-xl px-2.5 py-1.5 transition-colors hover:bg-elevated/60">
                            <UAvatar :alt="displayName" size="xs" />
                            <div class="hidden sm:flex flex-col min-w-0">
                                <p class="text-sm font-medium text-highlighted leading-none truncate">{{ displayName }}</p>
                                <p class="text-xs text-muted leading-none mt-0.5">Profile</p>
                            </div>
                        </NuxtLink>
                    </div>
                </template>
            </UDashboardNavbar>

            <div
                class="flex-1 overflow-y-auto bg-linear-to-b from-muted/20 via-transparent to-transparent px-4 py-5 lg:px-6 lg:py-6">
                <slot />
            </div>
        </UDashboardPanel>
    </UDashboardGroup>
</template>

<script setup lang="ts">
const config = useRuntimeConfig();
const route = useRoute();

// Decode JWT to check admin role and get display name
const tokenCookie = useCookie('access_token');
const decodedToken = computed(() => {
    if (!tokenCookie.value) return null;
    try {
        const [, payload] = tokenCookie.value.split('.');
        if (!payload) return null;
        return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
    } catch { return null; }
});
const isAdmin = computed(() => decodedToken.value?.role === 'admin');
const displayName = computed(() => {
    const email: string = decodedToken.value?.email ?? '';
    return email.split('@')[0] ?? 'Profile';
});

const appName = config.public.appName;

const navItems = computed(() => {
    const items = [
        [{ label: 'Dashboard', to: '/dashboard', icon: 'i-heroicons-home', exactActiveClass: 'bg-primary/10 text-primary' }],
        [{ label: 'Learn', to: '/learn', icon: 'i-heroicons-academic-cap', activeClass: 'bg-primary/10 text-primary' }],
        [{ label: 'Playbooks', to: '/playbooks', icon: 'i-heroicons-clipboard-document-list', activeClass: 'bg-primary/10 text-primary' }],
        [{ label: 'Resources', to: '/resources', icon: 'i-heroicons-link', activeClass: 'bg-primary/10 text-primary' }],
        [{ label: 'Blog', to: '/blog', icon: 'i-heroicons-newspaper', activeClass: 'bg-primary/10 text-primary' }],
    ];
    return items;
});

const trackItems = [
    [{ label: 'Foundation', to: '/learn/foundation', icon: 'i-heroicons-circle-stack', activeClass: 'bg-primary/10 text-primary' }],
    [{ label: 'CI/CD', to: '/learn/ci-cd', icon: 'i-heroicons-arrow-path-rounded-square', activeClass: 'bg-primary/10 text-primary' }],
    [{ label: 'Security', to: '/learn/security', icon: 'i-heroicons-shield-check', activeClass: 'bg-primary/10 text-primary' }],
    [{ label: 'Observability', to: '/learn/observability', icon: 'i-heroicons-chart-bar-square', activeClass: 'bg-primary/10 text-primary' }],
    [{ label: 'Resilience', to: '/learn/resilience', icon: 'i-heroicons-bolt', activeClass: 'bg-primary/10 text-primary' }],
];

const currentTitle = computed(() => {
    if (route.path.startsWith('/learn')) return 'Learning Roadmap';
    if (route.path.startsWith('/blog')) return 'Blog';
    if (route.path.startsWith('/playbooks')) return 'Playbooks';
    if (route.path.startsWith('/resources')) return 'Resources';
    if (route.path.startsWith('/profile')) return 'Profile';
    return 'Dashboard';
});


</script>
