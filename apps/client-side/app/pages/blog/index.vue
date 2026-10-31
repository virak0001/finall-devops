<template>
  <div class="min-h-screen bg-white text-slate-900">
    <div class="pointer-events-none absolute inset-0 overflow-hidden">
      <div class="absolute -top-24 -left-28 h-72 w-72 rounded-full bg-teal-300/20 blur-3xl" />
      <div class="absolute top-28 right-0 h-80 w-80 rounded-full bg-amber-300/20 blur-3xl" />
    </div>

    <header class="relative mx-auto flex w-full max-w-6xl items-center justify-between px-4 py-5 sm:px-6 lg:px-8">
      <NuxtLink to="/" class="flex items-center gap-3 shrink-0">
        <div class="flex size-10 items-center justify-center rounded-xl bg-linear-to-br from-teal-500 to-amber-400 shadow-md">
          <UIcon name="i-heroicons-cog-6-tooth" class="size-5 text-white" />
        </div>
        <div class="hidden sm:block">
          <p class="text-sm font-semibold tracking-wide">DevOps Learning Hub</p>
          <p class="text-xs text-slate-500">Learn by shipping</p>
        </div>
      </NuxtLink>

      <nav class="absolute left-1/2 -translate-x-1/2 hidden md:flex items-center gap-1 rounded-full border border-slate-200 bg-white/80 px-2 py-1.5 shadow-sm backdrop-blur">
        <NuxtLink
          v-for="link in navLinks"
          :key="link.to"
          :to="link.to"
          class="rounded-full px-4 py-1.5 text-sm font-medium text-slate-600 transition-colors hover:bg-slate-100 hover:text-slate-900"
          :active-class="'bg-slate-100 text-slate-900 font-semibold'"
        >
          {{ link.label }}
        </NuxtLink>
        <UColorModeButton size="xs" variant="ghost" color="neutral" class="ml-1" />
      </nav>

      <div class="flex items-center gap-2 shrink-0">
        <NuxtLink to="/login">
          <UButton variant="ghost" color="neutral" size="sm">Sign in</UButton>
        </NuxtLink>
        <NuxtLink v-if="isSignedIn" to="/dashboard">
          <UButton color="primary" size="sm" trailing-icon="i-heroicons-arrow-right">Dashboard</UButton>
        </NuxtLink>
        <NuxtLink v-else to="/register">
          <UButton color="primary" size="sm" trailing-icon="i-heroicons-arrow-right">Get Started</UButton>
        </NuxtLink>
      </div>
    </header>

    <main class="relative mx-auto w-full max-w-3xl px-4 pb-24 pt-12 sm:px-6 lg:px-8">
      <!-- Page heading -->
      <section class="mb-12">
        <h1 class="text-4xl font-bold tracking-tight text-slate-900 sm:text-5xl">Latest Articles</h1>
        <p class="mt-4 text-lg text-slate-500 leading-relaxed">
          Notes on DevOps, backend architecture, and practical implementation lessons from building this platform.
        </p>
      </section>

      <!-- Skeletons -->
      <div v-if="pending" class="space-y-10">
        <div v-for="i in 3" :key="i" class="space-y-3">
          <USkeleton class="h-52 w-full rounded-2xl" />
          <USkeleton class="h-4 w-28 rounded" />
          <USkeleton class="h-6 w-3/4 rounded" />
          <USkeleton class="h-4 w-full rounded" />
        </div>
      </div>

      <!-- Articles list -->
      <div v-else-if="posts?.length" class="space-y-14">
        <NuxtLink
          v-for="post in posts"
          :key="post.id"
          :to="`/blog/${post.slug}`"
          class="group block"
        >
          <!-- Cover gradient banner -->
          <div
            class="h-52 w-full rounded-2xl bg-linear-to-br transition-opacity group-hover:opacity-90 sm:h-60"
            :class="postGradient(post.slug)"
          />

          <!-- Meta -->
          <div class="mt-4 flex items-center gap-3 text-sm text-slate-500">
            <time>{{ formatDate(post.createdAt) }}</time>
            <span class="text-slate-300">·</span>
            <span>{{ readTime(post.content) }}</span>
          </div>

          <!-- Title -->
          <h2 class="mt-2 text-2xl font-bold text-slate-900 transition-colors group-hover:text-teal-700 sm:text-3xl">
            {{ post.title }}
          </h2>

          <!-- Excerpt -->
          <p class="mt-3 line-clamp-2 text-base leading-relaxed text-slate-500">
            {{ stripMarkdown(post.content) }}
          </p>
        </NuxtLink>
      </div>

      <UAlert
        v-else
        color="neutral"
        variant="soft"
        title="No blog posts yet"
        description="Publish your first post from the admin panel."
      />
    </main>
  </div>
</template>

<script setup lang="ts">
import type { BlogPost } from '~/types/api';

definePageMeta({ layout: 'blank' });

const tokenCookie = useCookie('access_token');
const isSignedIn = computed(() => Boolean(tokenCookie.value));

const navLinks = [
  { label: 'Home', to: '/' },
  { label: 'Learn', to: '/learn' },
  { label: 'Playbooks', to: '/playbooks' },
  { label: 'Resources', to: '/resources' },
  { label: 'Blog', to: '/blog' },
  { label: 'About', to: '/about' },
];

const { data: posts, pending } = useFetch<BlogPost[]>('/api/blog');

const GRADIENTS = [
  'from-teal-400 to-cyan-600',
  'from-violet-400 to-purple-600',
  'from-rose-400 to-pink-600',
  'from-amber-400 to-orange-500',
  'from-emerald-400 to-green-600',
  'from-blue-400 to-indigo-600',
  'from-sky-400 to-teal-600',
  'from-fuchsia-400 to-violet-600',
];

function postGradient(slug: string): string {
  const hash = slug.split('').reduce((acc, c) => acc + c.charCodeAt(0), 0);
  return GRADIENTS[hash % GRADIENTS.length] ?? GRADIENTS[0]!;
}

function readTime(content: string): string {
  const words = content.trim().split(/\s+/).length;
  const mins = Math.max(1, Math.round(words / 200));
  return `${mins} min read`;
}

function formatDate(value: string) {
  return new Date(value).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function stripMarkdown(md: string): string {
  return md
    .replace(/```[\s\S]*?```/g, '')
    .replace(/`[^`]*`/g, '')
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/\*(.+?)\*/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/^[-*]\s+/gm, '')
    .replace(/\n+/g, ' ')
    .trim();
}
</script>
