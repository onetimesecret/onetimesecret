<template>
  <AuthView :heading="`Customize - ${domainId}`" headingId="signin-heading">
    <template #form>
      <AccountDomainBrandForm />
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
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import AuthView from '@/components/auth/AuthView.vue';
import AccountDomainBrandForm from '@/components/account/AccountDomainBrandForm.vue';

const route = useRoute();
const domainId = route.params.domain as string;

interface CustomDomainBrand {
  logo: string;
  primaryColor: string;
  description: string;
  fontFamily: string;
  buttonStyle: string;
}

const brandSettings = ref<CustomDomainBrand>({
  logo: '',
  primaryColor: '#000000',
  description: '',
  fontFamily: 'sans-serif',
  buttonStyle: 'rounded'
});

const fetchBrandSettings = async () => {
  try {
    const response = await fetch(`/api/v2/account/domains/${domainId}/brand`);
    if (!response.ok) {
      throw new Error('Failed to fetch brand settings');
    }
    const data = await response.json();
    brandSettings.value = data;
  } catch (error) {
    console.error('Error fetching brand settings:', error);
    throw ('Failed to fetch brand settings. Please try again.');
  }
};

onMounted(fetchBrandSettings);
</script>
