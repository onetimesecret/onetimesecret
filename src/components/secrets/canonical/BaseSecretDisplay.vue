<script setup lang="ts">
import { WindowService } from '@/services/window.service';

const siteHost = WindowService.get('site_host');

interface Props {
  displayPoweredBy: boolean;
}

defineProps<Props>();

</script>

<template>
  <div>
    <slot name="content"></slot>

    <slot name="warnings"></slot>

    <slot name="cta"></slot>

    <slot name="footer">
      <div class="pt-20 text-center text-xs text-gray-400 dark:text-gray-600">
        <div class="space-x-2">
          <a
            v-if="displayPoweredBy"
            :href="`https://${siteHost}`"
            class="hover:underline"
            rel="noopener noreferrer">
            {{ $t('powered-by-onetime-secret') }}
          </a>
          <span>·</span>
          <router-link
            to="/info/terms"
            class="hover:underline">
            {{ $t('terms') }}
          </router-link>
          <span>·</span>
          <router-link
            to="/info/privacy"
            class="hover:underline">
            {{ $t('privacy') }}
          </router-link>
        </div>
      </div>
    </slot>
  </div>
</template>
