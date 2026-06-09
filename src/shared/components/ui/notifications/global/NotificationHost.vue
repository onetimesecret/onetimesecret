<!-- src/shared/components/ui/notifications/global/NotificationHost.vue -->
<!--
  Store-connected harness that teleports a notification visual to <body>.
  Translates i18n keys, reads notificationsStore state, and wires dismiss.

  Swap the visual style via the `variant` prop:
    pill   — small corner pill, no dismiss button (default, current production style)
    card   — corner card with dismiss + progress bar
    banner — full-width bar with dismiss + progress bar

  Mount once in App.vue:  <NotificationHost />
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { computed } from 'vue';
import NotificationPill from './NotificationPill.vue';
import NotificationCard from './NotificationCard.vue';
import NotificationBanner from './NotificationBanner.vue';

type Variant = 'pill' | 'card' | 'banner';

interface Props {
  variant?: Variant;
}

const props = withDefaults(defineProps<Props>(), {
  variant: 'pill',
});

const { t, te } = useI18n();
const notifications = useNotificationsStore();

const translatedMessage = computed(() =>
  te(notifications.message) ? t(notifications.message) : notifications.message
);

const variantComponent = computed(() => ({
  pill: NotificationPill,
  card: NotificationCard,
  banner: NotificationBanner,
})[props.variant]);
</script>

<template>
  <Teleport to="body">
    <component
      :is="variantComponent"
      :show="notifications.isVisible"
      :message="translatedMessage"
      :severity="notifications.severity"
      :position="notifications.position"
      @dismiss="notifications.hide" />
  </Teleport>
</template>
