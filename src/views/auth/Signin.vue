<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/views/auth/Signin.vue -->
<template>
  <AuthView heading="Sign in to your account" headingId="signin-heading">
    <template #form>
      <SignInForm />
      <div class="mt-6 text-center">
        <ul class="space-y-2">
          <li>
            <router-link to="/forgot"
                         class="text-sm text-gray-600 dark:text-gray-400 hover:underline transition duration-300 ease-in-out"
                         aria-label="Forgot Password">
              {{ $t('web.login.forgot_your_password') }}
            </router-link>
          </li>
        </ul>
      </div>
    </template>
    <template #footer>
      <router-link to="/signup"
                   class="font-medium text-brand-600 hover:text-brand-500
                          dark:text-brand-400 dark:hover:text-brand-300
                          transition-colors duration-200">
        {{ $t('web.login.need_an_account') }}
      </router-link>
    </template>
  </AuthView>
</template>

<script setup lang="ts">
import AuthView from '@/components/auth/AuthView.vue';
import SignInForm from '@/components/auth/SignInForm.vue';
</script>
