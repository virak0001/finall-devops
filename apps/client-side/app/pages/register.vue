<template>
    <div class="min-h-screen flex items-center justify-center bg-linear-to-br from-teal-50 via-sky-50 to-slate-100 dark:from-slate-950 dark:via-slate-900 dark:to-slate-950 px-4 py-10">
        <div class="w-full max-w-sm">
            <!-- Brand -->
            <div class="flex flex-col items-center gap-3 mb-8">
                <div class="flex size-12 items-center justify-center rounded-2xl bg-linear-to-br from-teal-500 to-amber-400 shadow-lg">
                    <UIcon name="i-heroicons-cog-6-tooth" class="size-6 text-white" />
                </div>
                <div class="text-center">
                    <h1 class="text-xl font-bold text-highlighted">DevOps Learning Hub</h1>
                    <p class="text-sm text-muted">Create your account</p>
                </div>
            </div>

            <UCard class="shadow-xl">
                <form class="flex flex-col gap-4" @submit.prevent="handleRegister">
                    <div class="grid grid-cols-2 gap-3">
                        <UFormField label="First name" name="firstName">
                            <UInput v-model="form.firstName" placeholder="Jane" size="lg" :ui="{ root: 'w-full' }" />
                        </UFormField>
                        <UFormField label="Last name" name="lastName">
                            <UInput v-model="form.lastName" placeholder="Doe" size="lg" :ui="{ root: 'w-full' }" />
                        </UFormField>
                    </div>

                    <UFormField label="Email" name="email">
                        <UInput v-model="form.email" type="email" placeholder="you@example.com" autocomplete="email"
                            size="lg" :ui="{ root: 'w-full' }" required />
                    </UFormField>

                    <UFormField label="Password" name="password">
                        <UInput v-model="form.password" :type="showPassword ? 'text' : 'password'"
                            placeholder="••••••••" size="lg" :ui="{ root: 'w-full' }" required>
                            <template #trailing>
                                <UButton :icon="showPassword ? 'i-heroicons-eye-slash' : 'i-heroicons-eye'"
                                    variant="ghost" color="neutral" size="xs" tabindex="-1"
                                    @click="showPassword = !showPassword" />
                            </template>
                        </UInput>
                        <!-- Password strength -->
                        <div v-if="form.password" class="mt-2 flex gap-1">
                            <div v-for="i in 5" :key="i"
                                :class="['h-1 flex-1 rounded-full transition-colors', i <= passwordStrength ? strengthColor : 'bg-muted']" />
                        </div>
                    </UFormField>

                    <UFormField label="Confirm password" name="confirm">
                        <UInput v-model="form.confirm" :type="showPassword ? 'text' : 'password'"
                            placeholder="••••••••" size="lg"
                            :ui="{ root: 'w-full' }" required />
                    </UFormField>

                    <UAlert v-if="error" color="error" variant="soft" :ui="{ root: 'py-2' }">
                        {{ error }}
                    </UAlert>

                    <UButton type="submit" color="primary" size="lg" block :loading="loading"
                        :disabled="form.password !== form.confirm && form.confirm.length > 0">
                        Create account
                    </UButton>
                </form>

                <template #footer>
                    <p class="text-center text-sm text-muted">
                        Already have an account?
                        <NuxtLink to="/login" class="text-primary font-medium hover:underline ml-1">
                            Sign in
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

const form = reactive({ firstName: '', lastName: '', email: '', password: '', confirm: '' });
const showPassword = ref(false);
const loading = ref(false);
const error = ref('');

const passwordStrength = computed(() => {
    const p = form.password;
    let score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (/[A-Z]/.test(p)) score++;
    if (/[0-9]/.test(p)) score++;
    if (/[^A-Za-z0-9]/.test(p)) score++;
    return score;
});

const strengthColor = computed(() => {
    if (passwordStrength.value <= 1) return 'bg-red-400';
    if (passwordStrength.value <= 2) return 'bg-orange-400';
    if (passwordStrength.value <= 3) return 'bg-yellow-400';
    return 'bg-teal-500';
});

async function handleRegister() {
    error.value = '';
    if (form.password !== form.confirm) {
        error.value = 'Passwords do not match';
        return;
    }
    loading.value = true;
    try {
        const data = await $fetch<LoginResponse>('/api/auth/register', {
            method: 'POST',
            body: {
                email: form.email,
                password: form.password,
                firstName: form.firstName || undefined,
                lastName: form.lastName || undefined,
            },
        });
        const accessToken = useCookie('access_token', { maxAge: 900, path: '/' });
        const refreshToken = useCookie('refresh_token', { maxAge: 604800, path: '/', httpOnly: false });
        accessToken.value = data.accessToken;
        refreshToken.value = data.refreshToken;
        await navigateTo('/dashboard');
    } catch (e: unknown) {
        error.value = (e as { data?: { message?: string } })?.data?.message ?? 'Registration failed';
    } finally {
        loading.value = false;
    }
}
</script>
