<!-- eslint-disable vue/multi-word-component-names -->
<script setup lang="ts">
import SignInForm from '@/components/auth/SignInForm.vue';

const shrimp = window.shrimp;
</script>

<template>
  <div>
    <section class="mb-8">
      <h3 class="text-2xl font-semibold mb-4 text-gray-900 dark:text-gray-100"
          aria-label="Sign In">
        {{ $t('web.login.enter_your_credentials') }}
      </h3>

      <SignInForm :shrimp="shrimp" />
    </section>

    <div class="text-center">
      <ul class="space-y-2">
        <li>
          <a href="/signup"
             class="text-sm text-gray-600 dark:text-gray-400 hover:underline transition duration-300 ease-in-out"
             aria-label="Sign Up">
            {{ $t('web.login.need_an_account') }}
          </a>
        </li>
        <li>
          <a href="/forgot"
             class="text-sm text-gray-600 dark:text-gray-400 hover:underline transition duration-300 ease-in-out"
             aria-label="Forgot Password">
            {{ $t('web.login.forgot_your_password') }}
          </a>
        </li>
      </ul>
    </div>
  </div>
</template>
