<template>
    <div class="min-h-screen flex items-center justify-center bg-linear-to-br from-teal-50 via-sky-50 to-slate-100 dark:from-slate-950 dark:via-slate-900 dark:to-slate-950 px-4">
        <div class="w-full max-w-sm">
            <!-- Brand -->
            <div class="flex flex-col items-center gap-3 mb-8">
                <div class="flex size-12 items-center justify-center rounded-2xl bg-linear-to-br from-teal-500 to-amber-400 shadow-lg">
                    <UIcon name="i-heroicons-cog-6-tooth" class="size-6 text-white" />
                </div>
                <div class="text-center">
                    <h1 class="text-xl font-bold text-highlighted">DevOps Learning Hub</h1>
                    <p class="text-sm text-muted">Sign in to your account</p>
                </div>
            </div>

            <UCard class="shadow-xl">
                <form class="flex flex-col gap-4" @submit.prevent="handleLogin">
                    <UFormField label="Email" name="email">
                        <UInput v-model="form.email" type="email" placeholder="you@example.com" autocomplete="email"
                            size="lg" :ui="{ root: 'w-full' }" required />
                    </UFormField>

                    <UFormField label="Password" name="password">
                        <UInput v-model="form.password" :type="showPassword ? 'text' : 'password'"
                            placeholder="••••••••" size="lg"
                            :ui="{ root: 'w-full' }">
                            <template #trailing>
                                <UButton :icon="showPassword ? 'i-heroicons-eye-slash' : 'i-heroicons-eye'"
                                    variant="ghost" color="neutral" size="xs" tabindex="-1"
                                    @click="showPassword = !showPassword" />
                            </template>
                        </UInput>
                    </UFormField>

                    <UAlert v-if="error" color="error" variant="soft" :ui="{ root: 'py-2' }">
                        {{ error }}
                    </UAlert>

                    <UButton type="submit" color="primary" size="lg" block :loading="loading">
                        Sign in
                    </UButton>
                </form>

                <template #footer>
                    <p class="text-center text-sm text-muted">
                        Don't have an account?
                        <NuxtLink to="/register" class="text-primary font-medium hover:underline ml-1">
                            Sign up
                        </NuxtLink>
                    </p>
                </template>
            </UCard>
        </div>
    </div>
</template>

<script setup lang="ts">
import type { LoginResponse } from '~/types/api';

definePageMeta({ layout: 'blank' });

const form = reactive({ email: '', password: '' });
const showPassword = ref(false);
const loading = ref(false);
const error = ref('');

async function handleLogin() {
    error.value = '';
    loading.value = true;
    try {
        const data = await $fetch<LoginResponse>('/api/auth/login', {
            method: 'POST',
            body: { email: form.email, password: form.password },
        });
        const accessToken = useCookie('access_token', { maxAge: 900, path: '/' });
        const refreshToken = useCookie('refresh_token', { maxAge: 604800, path: '/', httpOnly: false });
        accessToken.value = data.accessToken;
        refreshToken.value = data.refreshToken;
        await navigateTo('/dashboard');
    } catch (e: unknown) {
        error.value = (e as { data?: { message?: string } })?.data?.message ?? 'Invalid credentials';
    } finally {
        loading.value = false;
    }
}
</script>
