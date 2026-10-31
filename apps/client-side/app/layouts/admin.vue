<template>
    <UDashboardGroup>
        <UDashboardSidebar collapsible
            :ui="{ body: 'flex flex-col gap-1 p-2', footer: 'border-t border-default px-2 py-3' }">
            <template #header>
                <NuxtLink to="/admin" class="flex items-center gap-3 px-2 py-1 min-w-0">
                    <div
                        class="flex size-9 items-center justify-center rounded-xl bg-linear-to-br from-rose-500 to-orange-400 shadow-sm shrink-0">
                        <UIcon name="i-heroicons-cog-8-tooth" class="size-4 text-white" />
                    </div>
                    <div class="min-w-0">
                        <p class="truncate text-sm font-semibold text-highlighted">{{ appName }}</p>
                        <p class="truncate text-xs text-muted">Admin workspace</p>
                    </div>
                </NuxtLink>
            </template>

            <UNavigationMenu orientation="vertical" :items="adminNavItems" content-orientation="vertical"
                :ui="{ root: 'w-full', link: 'rounded-xl px-3 py-2.5' }" />

            <template #footer>
                <NuxtLink to="/dashboard"
                    class="flex items-center gap-2 rounded-xl px-3 py-2.5 text-sm text-muted hover:text-highlighted hover:bg-elevated/60 transition-colors">
                    <UIcon name="i-heroicons-arrow-left-circle" class="size-4 shrink-0" />
                    Back to Learning
                </NuxtLink>
            </template>
        </UDashboardSidebar>

        <UDashboardPanel grow>
            <UDashboardNavbar :title="currentTitle" :toggle="true" toggle-side="left" :ui="{ root: 'border-0' }">
                <template #left>
                    <div class="flex flex-col">
                        <span class="text-sm font-semibold text-highlighted">{{ currentTitle }}</span>
                        <span class="text-xs text-muted">Content management</span>
                    </div>
                </template>

                <template #right>
                    <NuxtLink to="/profile"
                        class="flex items-center gap-2.5 rounded-xl px-2.5 py-1.5 transition-colors hover:bg-elevated/60">
                        <UAvatar :alt="displayName" size="xs" />
                        <div class="hidden sm:flex flex-col min-w-0">
                            <p class="text-sm font-medium text-highlighted leading-none truncate">{{ displayName }}</p>
                            <p class="text-xs text-muted leading-none mt-0.5">Profile</p>
                        </div>
                    </NuxtLink>
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

const tokenCookie = useCookie('access_token');
const decodedToken = computed(() => {
    if (!tokenCookie.value) return null;
    try {
        const [, payload] = tokenCookie.value.split('.');
        if (!payload) return null;
        return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
    } catch { return null; }
});
const displayName = computed(() => {
    const email: string = decodedToken.value?.email ?? '';
    return email.split('@')[0] ?? 'Profile';
});

const appName = config.public.appName;

const adminNavItems = [
    [{ label: 'Overview', to: '/admin', icon: 'i-heroicons-squares-2x2', exactActiveClass: 'bg-error/10 text-error' }],
    [{ label: 'Learning Content', to: '/admin/learn', icon: 'i-heroicons-academic-cap', activeClass: 'bg-error/10 text-error' }],
    [{ label: 'Blog', to: '/admin/blog', icon: 'i-heroicons-pencil-square', activeClass: 'bg-error/10 text-error' }],
    [{ label: 'Playbooks', to: '/admin/playbooks', icon: 'i-heroicons-clipboard-document-list', activeClass: 'bg-error/10 text-error' }],
    [{ label: 'Resources', to: '/admin/resources', icon: 'i-heroicons-link', activeClass: 'bg-error/10 text-error' }],
];

const currentTitle = computed(() => {
    if (route.path === '/admin') return 'Content Management';
    if (route.path.startsWith('/admin/learn')) return 'Learning Content';
    if (route.path.startsWith('/admin/blog')) return 'Blog';
    if (route.path.startsWith('/admin/playbooks')) return 'Playbooks';
    if (route.path.startsWith('/admin/resources')) return 'Resources';
    return 'Admin';
});
</script>
