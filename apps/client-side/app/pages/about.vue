<template>
    <div>
        <!-- Hero -->
        <section class="flex flex-col items-center pt-16 pb-20 text-center sm:pt-24">
            <UAvatar text="RV" size="3xl" :ui="{ root: 'size-14 ring-1 ring-default', fallback: 'font-semibold' }" />

            <h1 class="mt-8 text-4xl font-bold leading-[1.1] tracking-tight text-highlighted sm:text-5xl">
                Hey, I'm Ran Virak
            </h1>
            <p class="mt-3 text-base text-muted">Developer</p>

            <p class="mt-5 max-w-lg text-sm leading-relaxed text-muted sm:text-base">
                A developer focused on continuous growth and technical excellence. I work across
                programming, security systems, and DevOps infrastructure — building secure, scalable
                solutions through hands-on exploration.
            </p>

            <div class="mt-8 flex flex-wrap items-center justify-center gap-x-5 gap-y-3">
                <UButton to="/learn" color="neutral" variant="solid" size="md">Explore the tracks</UButton>
                <span class="inline-flex items-center gap-2 text-sm text-muted">
                    <span class="relative flex size-2">
                        <span class="absolute inline-flex size-full animate-ping rounded-full bg-primary opacity-60" />
                        <span class="relative inline-flex size-2 rounded-full bg-primary" />
                    </span>
                    Open to collaboration
                </span>
            </div>

            <div class="mt-8 flex items-center gap-4">
                <ULink v-for="s in socialLinks" :key="s.label" :to="s.to" target="_blank" :aria-label="s.label"
                    class="text-dimmed transition-colors hover:text-highlighted">
                    <UIcon :name="s.icon" class="size-5" />
                </ULink>
            </div>
        </section>

        <!-- Focus areas as tilted cards — the same visual beat as the home page gallery -->
        <section class="flex items-center justify-center gap-4 pb-24 sm:gap-6">
            <div v-for="(card, i) in focusAreas" :key="card.name" :class="[
                'flex aspect-4/3 w-full max-w-52 flex-col justify-between rounded-xl border border-default bg-elevated p-4 transition-transform duration-300 hover:rotate-0 hover:scale-105',
                i === 0 ? '-rotate-3' : i === 1 ? 'rotate-1' : 'rotate-3',
                i === 1 ? '' : 'hidden sm:flex',
            ]">
                <UIcon :name="card.icon" class="size-6 text-primary" />
                <div>
                    <p class="text-sm font-semibold text-highlighted">{{ card.name }}</p>
                    <p class="mt-0.5 text-xs text-muted">{{ card.caption }}</p>
                </div>
            </div>
        </section>

        <!-- Why / How, side by side -->
        <section class="grid gap-12 pb-24 sm:grid-cols-2">
            <div>
                <h2 class="text-xl font-semibold tracking-tight text-highlighted">Why I built this</h2>
                <p class="mt-4 text-sm leading-relaxed text-muted">
                    DevOps Learning Hub reflects how I learn best — structured tracks, hands-on tasks,
                    and reusable playbooks. I built it to replace scattered blog posts and random
                    tutorials with a clear path that mirrors real platform engineering work.
                </p>
            </div>
            <div>
                <h2 class="text-xl font-semibold tracking-tight text-highlighted">How I approach it</h2>
                <p class="mt-4 text-sm leading-relaxed text-muted">
                    Security, scalability, and maintainability in every layer — from API and database
                    design through to the deployment pipeline. The platform practices what it teaches,
                    built with the same tools the curriculum covers.
                </p>
            </div>
        </section>

        <!-- Skills & tools -->
        <section class="pb-24">
            <h2 class="text-xl font-semibold tracking-tight text-highlighted">Skills &amp; tools</h2>
            <p class="mt-1 text-sm text-muted">What I work with day to day</p>
            <div class="mt-6 flex flex-wrap gap-2">
                <span v-for="skill in skills" :key="skill"
                    class="rounded-full border border-default bg-elevated px-3 py-1.5 text-xs text-toned">
                    {{ skill }}
                </span>
            </div>
        </section>

        <!-- Architecture -->
        <section class="pb-24">
            <h2 class="text-xl font-semibold tracking-tight text-highlighted">How this platform is built</h2>
            <p class="mt-3 text-sm leading-relaxed text-muted">
                A microservice architecture — each domain (auth, learning, playbooks, resources) is a
                self-contained service with its own responsibility boundary. Services talk over
                well-defined APIs, so each stays independently deployable.
            </p>

            <div class="mt-8 rounded-2xl border border-default bg-elevated p-6 sm:p-8">
                <div class="flex flex-col items-center gap-3">
                    <template v-for="(tier, tierIndex) in architecture" :key="tier.label">
                        <!-- Connector between tiers -->
                        <div v-if="tierIndex > 0" class="flex flex-col items-center text-dimmed">
                            <div class="h-5 w-px bg-border" />
                            <UIcon name="i-heroicons-chevron-down" class="-mt-1 size-3.5" />
                        </div>

                        <div :class="[
                            'grid w-full gap-3',
                            tier.nodes.length > 2 ? 'sm:grid-cols-2 lg:grid-cols-4'
                                : tier.nodes.length === 2 ? 'max-w-sm grid-cols-2' : 'max-w-xs',
                        ]">
                            <div v-for="node in tier.nodes" :key="node.name"
                                class="flex flex-col items-center gap-1.5 rounded-xl border border-default bg-default px-4 py-4 text-center">
                                <UIcon :name="node.icon" class="size-5 text-primary" />
                                <p class="text-sm font-semibold text-highlighted">{{ node.name }}</p>
                                <p class="text-xs text-muted">{{ node.description }}</p>
                            </div>
                        </div>
                    </template>
                </div>
            </div>
        </section>

        <!-- CTA -->
        <section class="pb-24">
            <div class="rounded-2xl border border-default bg-elevated px-6 py-10 text-center sm:px-12">
                <h2 class="text-2xl font-semibold tracking-tight text-highlighted">
                    Want to learn DevOps with a clear system?
                </h2>
                <p class="mx-auto mt-3 max-w-md text-sm leading-relaxed text-muted">
                    Create an account, pick a track, and build production-ready skills with measurable wins.
                </p>
                <div class="mt-7 flex flex-wrap items-center justify-center gap-3">
                    <UButton :to="isSignedIn ? '/dashboard' : '/register'" color="neutral" size="md">
                        {{ isSignedIn ? 'Open dashboard' : 'Get started free' }}
                    </UButton>
                    <UButton to="/learn" color="neutral" variant="ghost" size="md">Explore tracks</UButton>
                </div>
            </div>
        </section>
    </div>
</template>

<script setup lang="ts">
definePageMeta({ layout: 'site' });

const { socialLinks } = useSiteNav();

const tokenCookie = useCookie('access_token');
const isSignedIn = computed(() => Boolean(tokenCookie.value));

const focusAreas = [
    { name: 'Programming', caption: 'Node, Vue, PHP', icon: 'i-heroicons-code-bracket' },
    { name: 'Security', caption: 'Auth, guards, hardening', icon: 'i-heroicons-shield-check' },
    { name: 'Infrastructure', caption: 'Docker, CI/CD, AWS', icon: 'i-heroicons-server-stack' },
];

// Brand logos would need @iconify-json/simple-icons, which the registry will not
// currently serve — so these are plain labels rather than empty icon slots.
const skills = [
    'Node.js',
    'Vue.js / Nuxt',
    'NestJS',
    'PHP',
    'PostgreSQL',
    'TypeORM',
    'Docker',
    'CI/CD',
    'AWS Lambda',
    'Kubernetes',
];

const architecture = [
    {
        label: 'client',
        nodes: [
            { name: 'Nuxt frontend', description: 'SSR / SPA client', icon: 'i-heroicons-computer-desktop' },
        ],
    },
    {
        label: 'gateway',
        nodes: [
            { name: 'NestJS API gateway', description: 'JWT auth · routing · guards', icon: 'i-heroicons-server' },
        ],
    },
    {
        label: 'services',
        nodes: [
            { name: 'Auth', description: 'JWT issue, refresh, validate', icon: 'i-heroicons-lock-closed' },
            { name: 'Learn', description: 'Tracks, lessons, progress', icon: 'i-heroicons-academic-cap' },
            { name: 'Playbooks', description: 'Operational runbooks', icon: 'i-heroicons-clipboard-document-list' },
            { name: 'Resources', description: 'Curated tools and links', icon: 'i-heroicons-book-open' },
        ],
    },
    {
        label: 'data',
        nodes: [
            { name: 'PostgreSQL', description: 'Persistent data', icon: 'i-heroicons-circle-stack' },
            { name: 'Docker', description: 'Containerised deploy', icon: 'i-heroicons-cube' },
        ],
    },
];
</script>
