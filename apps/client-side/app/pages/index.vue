<template>
    <div>
        <section class="flex flex-col items-center pt-16 pb-20 text-center sm:pt-24">
            <UAvatar :ui="{ root: 'size-14 ring-1 ring-default' }" icon="i-heroicons-cog-6-tooth" size="3xl" />

            <h1 class="mt-8 max-w-xl text-4xl font-bold leading-[1.1] tracking-tight text-highlighted sm:text-5xl">
                Master DevOps through practical tracks
            </h1>

            <p class="mt-5 max-w-lg text-sm leading-relaxed text-muted sm:text-base">
                Skip scattered docs and random tutorials. A clear path across CI/CD, security,
                observability, and cloud workflows — with measurable outcomes.
            </p>

            <div class="mt-8 flex flex-wrap items-center justify-center gap-x-5 gap-y-3">
                <UButton :to="isSignedIn ? '/dashboard' : '/register'" color="neutral" variant="solid" size="md">
                    {{ isSignedIn ? 'Continue learning' : 'Start learning free' }}
                </UButton>
                <NuxtLink to="/learn"
                    class="inline-flex items-center gap-2 text-sm text-muted transition-colors hover:text-highlighted">
                    <span class="relative flex size-2">
                        <span class="absolute inline-flex size-full animate-ping rounded-full bg-primary opacity-60" />
                        <span class="relative inline-flex size-2 rounded-full bg-primary" />
                    </span>
                    6 tracks available now
                </NuxtLink>
            </div>

            <div class="mt-8 flex items-center gap-4">
                <ULink v-for="s in socialLinks" :key="s.label" :to="s.to" target="_blank" :aria-label="s.label"
                    class="text-dimmed transition-colors hover:text-highlighted">
                    <UIcon :name="s.icon" class="size-5" />
                </ULink>
            </div>
        </section>

        <section class="flex items-center justify-center gap-4 pb-24 sm:gap-6">
            <div v-for="(card, i) in galleryCards" :key="card.name" :class="[
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

        <!-- About + Learning path, side by side like About Me / Work Experience -->
        <section class="grid gap-12 pb-24 sm:grid-cols-2">
            <div>
                <h2 class="text-xl font-semibold tracking-tight text-highlighted">About the platform</h2>
                <p class="mt-4 text-sm leading-relaxed text-muted">
                    A structured DevOps curriculum built for people who learn by shipping. Each track
                    moves from foundation to production confidence through short, hands-on lessons,
                    backed by operational playbooks you can reuse on real systems. Progress is tracked
                    per lesson, so learning stays measurable instead of open-ended.
                </p>
            </div>

            <div>
                <h2 class="text-xl font-semibold tracking-tight text-highlighted">Learning path</h2>
                <div class="mt-4 space-y-3">
                    <div v-for="track in tracks" :key="track.name" class="flex items-center gap-3 text-sm">
                        <span class="shrink-0 text-xs tabular-nums text-dimmed">{{ track.duration }}</span>
                        <span class="h-px flex-1 bg-border" />
                        <span class="shrink-0 font-medium text-highlighted">{{ track.name }}</span>
                    </div>
                </div>
            </div>
        </section>

        <!-- Latest articles -->
        <section class="pb-24">
            <h2 class="text-xl font-semibold tracking-tight text-highlighted">Latest articles</h2>
            <p class="mt-1 text-sm text-muted">Recent writing from the hub</p>

            <div v-if="pending" class="mt-10 space-y-10">
                <div v-for="n in 3" :key="n" class="space-y-3">
                    <div class="h-3 w-24 animate-pulse rounded bg-elevated" />
                    <div class="h-5 w-2/3 animate-pulse rounded bg-elevated" />
                    <div class="h-4 w-full animate-pulse rounded bg-elevated" />
                </div>
            </div>

            <div v-else-if="latestPosts.length" class="mt-10 space-y-10">
                <article v-for="post in latestPosts" :key="post.id">
                    <p class="text-xs text-dimmed">{{ formatDate(post.createdAt) }}</p>
                    <h3 class="mt-2 text-base font-semibold text-highlighted">{{ post.title }}</h3>
                    <p class="mt-2 text-sm leading-relaxed text-muted">{{ excerpt(post.content) }}</p>
                    <NuxtLink :to="`/blog/${post.slug}`" class="mt-3 inline-block text-sm text-primary hover:underline">
                        Read article
                    </NuxtLink>
                </article>
            </div>

            <p v-else class="mt-10 text-sm text-muted">No articles published yet.</p>
        </section>

        <!-- Testimonials -->
        <section class="pb-24">
            <UCarousel v-slot="{ item }" :items="testimonials" dots loop class="w-full" :ui="{ item: 'basis-full' }">
                <div class="rounded-2xl border border-default bg-elevated px-6 py-10 text-center sm:px-12">
                    <UIcon name="i-heroicons-chat-bubble-left-right" class="mx-auto size-6 text-dimmed" />
                    <p class="mx-auto mt-5 max-w-lg text-sm leading-relaxed text-toned">"{{ item.quote }}"</p>
                    <div class="mt-6 flex items-center justify-center gap-3">
                        <UAvatar :alt="item.name" size="sm" />
                        <div class="text-left">
                            <p class="text-sm font-medium text-highlighted">{{ item.name }}</p>
                            <p class="text-xs text-muted">{{ item.role }}</p>
                        </div>
                    </div>
                </div>
            </UCarousel>
        </section>

        <!-- FAQ -->
        <section class="pb-24">
            <h2 class="text-xl font-semibold tracking-tight text-highlighted">Frequently asked questions</h2>
            <p class="mt-1 text-sm text-muted">Answers to common questions about the tracks and platform.</p>
            <UAccordion :items="faqItems" class="mt-8" :ui="{
                item: 'border border-default rounded-xl mb-2 px-4',
                trigger: 'py-3.5 text-sm font-medium',
                body: 'text-sm text-muted pb-4',
            }" />
        </section>
    </div>
</template>

<script setup lang="ts">
import type { BlogPost } from '~/types/api';

definePageMeta({ layout: 'site' });

const { socialLinks } = useSiteNav();

const tokenCookie = useCookie('access_token');
const isSignedIn = computed(() => Boolean(tokenCookie.value));

const galleryCards = [
    { name: 'CI/CD', caption: 'Pipelines that fail loudly', icon: 'i-heroicons-arrow-path-rounded-square' },
    { name: 'Cloud & GitOps', caption: 'Declarative, reviewable infra', icon: 'i-heroicons-cloud' },
    { name: 'Observability', caption: 'Know before your users do', icon: 'i-heroicons-chart-bar-square' },
];

const tracks = [
    { name: 'Foundation', duration: '1–2 weeks' },
    { name: 'CI/CD', duration: '1 week' },
    { name: 'Security', duration: '1 week' },
    { name: 'Observability', duration: '1 week' },
    { name: 'Resilience', duration: '1 week' },
    { name: 'Cloud & GitOps', duration: '1–2 weeks' },
];

const { data: posts, pending } = await useFetch<BlogPost[]>('/api/blog', {
    default: () => [] as BlogPost[],
});

const latestPosts = computed(() =>
    [...(posts.value ?? [])]
        .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
        .slice(0, 3),
);

function formatDate(value: string): string {
    return new Date(value).toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
    });
}

/** Strip the common markdown syntax so a card shows prose, not symbols. */
function excerpt(content: string, max = 160): string {
    const plain = content
        .replace(/```[\s\S]*?```/g, '')
        .replace(/!\[[^\]]*\]\([^)]*\)/g, '')
        .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
        .replace(/^#{1,6}\s+/gm, '')
        .replace(/[*_`>#-]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
    return plain.length > max ? `${plain.slice(0, max).trimEnd()}…` : plain;
}

const testimonials = [
    {
        quote: 'The playbooks were the part that stuck. I stopped reading about incident response and actually ran one, which changed how I think about on-call.',
        name: 'Placeholder Name',
        role: 'Platform Engineer',
    },
    {
        quote: 'Each track ends with something I have deployed myself. That is the difference between this and the tutorials I abandoned.',
        name: 'Placeholder Name',
        role: 'Backend Developer',
    },
    {
        quote: 'Progress tracking sounds minor until you have it. Seeing lessons close out kept me going through the security track.',
        name: 'Placeholder Name',
        role: 'SRE',
    },
];

const faqItems = [
    {
        label: 'Do I need prior DevOps experience?',
        content:
            'No. The Foundation track assumes only basic command-line comfort and builds from there. Later tracks each state their prerequisites.',
    },
    {
        label: 'How long does a track take?',
        content:
            'Most take about a week of part-time study; Foundation and Cloud & GitOps run one to two weeks. Lessons are short by design so progress stays steady.',
    },
    {
        label: 'What is the difference between tracks and playbooks?',
        content:
            'Tracks teach concepts in sequence. Playbooks are scenario-driven runbooks you execute — and can reuse on your own systems afterwards.',
    },
    {
        label: 'Is it free?',
        content: 'Creating an account and starting a track is free.',
    },
];
</script>
