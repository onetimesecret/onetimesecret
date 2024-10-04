<!-- eslint-disable vue/multi-word-component-names -->
<script setup lang="ts">
import SignInForm from '@/components/auth/SignInForm.vue';

</script>

<template>
  <div class="my-20">
    <section class="my-8">
      <h3 class="text-2xl font-semibold mb-4 text-gray-900 dark:text-gray-100"
          aria-label="Sign In">
        {{ $t('web.login.enter_your_credentials') }}
      </h3>

      <SignInForm />
    </section>

    <div class="text-center">
      <ul class="space-y-2">
        <li>
          <router-link to="/signup"
                       class="text-sm text-gray-600 dark:text-gray-400 hover:underline transition duration-300 ease-in-out"
                       aria-label="Sign Up">
            {{ $t('web.login.need_an_account') }}
          </router-link>
        </li>
        <li>
          <router-link to="/forgot"
                       class="text-sm text-gray-600 dark:text-gray-400 hover:underline transition duration-300 ease-in-out"
                       aria-label="Forgot Password">
            {{ $t('web.login.forgot_your_password') }}
          </router-link>
        </li>
      </ul>
    </div>
  </div>
</template>
