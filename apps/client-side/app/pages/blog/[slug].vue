<template>
  <div class="min-h-screen bg-white text-slate-900">
    <main class="mx-auto w-full max-w-3xl px-4 pb-24 pt-10 sm:px-6 lg:px-8">

      <!-- Back link -->
      <NuxtLink to="/blog" class="inline-flex items-center gap-1.5 text-sm text-slate-500 hover:text-slate-900 transition-colors">
        <UIcon name="i-heroicons-arrow-left" class="size-4" />
        Blog
      </NuxtLink>

      <!-- Skeleton -->
      <div v-if="pendingPost" class="mt-8 space-y-4">
        <USkeleton class="h-52 w-full rounded-2xl" />
        <USkeleton class="h-4 w-32 rounded" />
        <USkeleton class="h-8 w-3/4 rounded" />
        <USkeleton class="h-48 rounded-xl" />
      </div>

      <template v-else-if="post">
        <!-- Cover banner -->
        <div
          class="mt-8 h-52 w-full rounded-2xl bg-linear-to-br sm:h-64"
          :class="postGradient(post.slug)"
        />

        <!-- Meta -->
        <div class="mt-6 flex items-center gap-3 text-sm text-slate-500">
          <time>{{ formatDate(post.createdAt) }}</time>
          <span class="text-slate-300">·</span>
          <span>{{ readTime(post.content) }}</span>
          <span class="text-slate-300">·</span>
          <UButton
            size="xs"
            :color="completed ? 'success' : 'neutral'"
            :variant="completed ? 'soft' : 'outline'"
            :leading-icon="completed ? 'i-heroicons-check-circle' : undefined"
            @click="toggleComplete"
          >
            {{ completed ? 'Completed' : 'Mark Complete' }}
          </UButton>
        </div>

        <!-- Title -->
        <h1 class="mt-4 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">{{ post.title }}</h1>

        <!-- Article body -->
        <div class="md-prose mt-8" v-html="renderedHtml" />
      </template>

      <UAlert
        v-else
        class="mt-8"
        color="warning"
        variant="soft"
        title="Post not found"
        description="This blog post may have been removed."
      />

      <!-- Comments -->
      <section v-if="post" class="mt-16 border-t border-slate-100 pt-10">
        <div class="flex items-center justify-between gap-3 mb-6">
          <h2 class="text-xl font-bold text-slate-900">Comments</h2>
          <UBadge color="neutral" variant="soft">{{ comments?.length || 0 }}</UBadge>
        </div>

        <form v-if="isSignedIn" class="space-y-3" @submit.prevent="submitComment">
          <UTextarea v-model="newComment" :rows="4" placeholder="Write your comment…" class="w-full" />
          <div class="flex items-center justify-between gap-2">
            <p v-if="commentError" class="text-sm text-error">{{ commentError }}</p>
            <UButton type="submit" :loading="submitting" color="primary" class="ml-auto">Post Comment</UButton>
          </div>
        </form>

        <UAlert
          v-else
          color="neutral"
          variant="soft"
          title="Sign in to comment"
          description="You can read all comments publicly, but posting requires an account."
        />

        <div v-if="pendingComments" class="mt-6 space-y-3">
          <USkeleton v-for="i in 3" :key="i" class="h-20 rounded-xl" />
        </div>

        <div v-else-if="comments?.length" class="mt-6 space-y-4">
          <div
            v-for="comment in comments"
            :key="comment.id"
            class="rounded-xl border border-slate-100 bg-slate-50 px-4 py-3"
          >
            <div class="flex items-center justify-between gap-2">
              <p class="text-sm font-semibold text-slate-900">{{ comment.authorName }}</p>
              <p class="text-xs text-slate-400">{{ formatDate(comment.createdAt) }}</p>
            </div>
            <p class="mt-2 whitespace-pre-wrap text-sm leading-relaxed text-slate-600">{{ comment.content }}</p>
          </div>
        </div>

        <p v-else class="mt-6 text-sm text-slate-400">No comments yet. Be the first to share feedback.</p>
      </section>
    </main>
  </div>
</template>

<script setup lang="ts">
import type { BlogComment, BlogPost } from '~/types/api';

definePageMeta({ layout: 'blank' });

const route = useRoute();
const slug = computed(() => String(route.params.slug || ''));
const tokenCookie = useCookie('access_token');
const isSignedIn = computed(() => Boolean(tokenCookie.value));

const { data: post, pending: pendingPost } = useFetch<BlogPost>(() => `/api/blog/${slug.value}`);
const {
  data: comments,
  pending: pendingComments,
  refresh: refreshComments,
} = useFetch<BlogComment[]>(() => `/api/blog/${slug.value}/comments`);

const newComment = ref('');
const commentError = ref('');
const submitting = ref(false);
const completed = ref(false);
const renderedHtml = ref('');

// ── Gradient cover ────────────────────────────────────────────────────────────
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

function postGradient(s: string): string {
  const hash = s.split('').reduce((acc, c) => acc + c.charCodeAt(0), 0);
  return GRADIENTS[hash % GRADIENTS.length];
}

function readTime(content: string): string {
  const words = content.trim().split(/\s+/).length;
  return `${Math.max(1, Math.round(words / 200))} min read`;
}

// renderMarkdown, escapeHtml, slugify are auto-imported from ~/utils/markdown.ts

// ── Completion ────────────────────────────────────────────────────────────────
async function loadCompletion() {
  if (!slug.value) return;
  if (isSignedIn.value) {
    try { completed.value = Boolean(await $fetch<boolean>(`/api/blog/${slug.value}/complete`)); }
    catch { completed.value = false; }
  } else {
    completed.value = Boolean(localStorage.getItem(`blog:completed:${slug.value}`));
  }
}

async function toggleComplete() {
  if (!slug.value) return;
  if (isSignedIn.value) {
    try { await $fetch(`/api/blog/${slug.value}/complete`, { method: 'POST' }); completed.value = true; }
    catch { /* ignore */ }
  } else {
    const key = `blog:completed:${slug.value}`;
    if (completed.value) { localStorage.removeItem(key); completed.value = false; }
    else { localStorage.setItem(key, '1'); completed.value = true; }
  }
}

// ── Comments ──────────────────────────────────────────────────────────────────
async function submitComment() {
  commentError.value = '';
  if (!newComment.value.trim()) { commentError.value = 'Comment cannot be empty.'; return; }
  submitting.value = true;
  try {
    await $fetch(`/api/blog/${slug.value}/comments`, { method: 'POST', body: { content: newComment.value.trim() } });
    newComment.value = '';
    await refreshComments();
  } catch (error: unknown) {
    commentError.value = (error as { data?: { message?: string } })?.data?.message || 'Unable to post comment right now.';
  } finally {
    submitting.value = false;
  }
}

function formatDate(value: string) {
  return new Date(value).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}

onMounted(() => loadCompletion());

watch(() => post.value, (p) => { renderedHtml.value = p?.content ? renderMarkdown(p.content) : ''; }, { immediate: true });
</script>
