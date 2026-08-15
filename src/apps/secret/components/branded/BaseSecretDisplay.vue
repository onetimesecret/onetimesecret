<!-- src/apps/secret/components/branded/BaseSecretDisplay.vue -->

<script setup lang="ts">
  /**
   * Core display component for branded secret workflows that provides consistent
   * layout and styling across both confirmation and reveal states.
   *
   * This component is specifically designed for custom branded deployments where
   * maintaining brand consistency is prioritized over marketing opportunities.
   * For the core Onetime Secret implementation, see the canonical SecretDisplayCase.
   *
   * @prop defaultTitle - Fallback title when branding is unavailable
   * @prop instructions - Optional pre-reveal instructions from domain branding
   * @prop domainBranding - Domain-specific styling configuration
   * @prop headingClass - Resolved heading font token (the heading_font-
   *   backfilled-by-font_family ladder lives in resolveHeadingFontClass);
   *   required so a missing binding is a type error, not a silent body-font
   *   heading. Callers scope the resolution themselves — the dashboard
   *   preview resolves the domain being edited, not the page identity.
   *
   * @slot logo - Domain logo or fallback icon
   * @slot content - Main content area (confirmation form or secret content)
   * @slot action-button - Action button slot (submit or copy)
   */
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { BrandSettings } from '@/schemas/shapes/v3/custom-domain';
  import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue';
  import { Composer, useI18n } from 'vue-i18n';

  const i18n = useI18n();

  const props = defineProps<{
    domainBranding: BrandSettings;
    cornerClass: string;
    fontClass: string;
    headingClass: string;
    defaultTitle?: string;
    previewI18n?: Composer;
    isRevealed?: boolean;
  }>();

  // Text expansion logic
  const textRef = ref<HTMLElement | null>(null);
  const isExpanded = ref(false);
  const isLongText = ref(false);

  const displayComposer = props.previewI18n || i18n;

  // Computed property for instructions text
  const instructions = computed(() => {
    const isPostReveal = props.isRevealed === true;
    const instructionsKey = isPostReveal
      ? 'instructions_post_reveal'
      : 'instructions_pre_reveal';
    const defaultKey = isPostReveal
      ? 'web.shared.post_reveal_default'
      : 'web.shared.pre_reveal_default';

    return props.domainBranding[instructionsKey]?.trim() ||
           displayComposer.t(defaultKey);
  });

  // Reusable computed properties. Note the clamp is `instructions-clamp`, a
  // class this component owns, not Tailwind's `line-clamp-6`: two sibling
  // components used to re-declare `.line-clamp-6` at a shallower line count,
  // so the clamp actually in force depended on stylesheet injection order.
  const textClasses = computed(() => ({
    'text-gray-600 dark:text-gray-400 text-xs sm:text-sm leading-relaxed': true,
    'instructions-clamp': !isExpanded.value,
  }));

  // Text length checking.
  //
  // Asks the clamped element whether it is actually overflowing rather than
  // re-deriving the clamp height from line-height and a line count. A derived
  // threshold is a second copy of the clamp that can disagree with the CSS —
  // which is what produced a "Show More" toggle over text that was already
  // fully visible. Overflow is measured in the layout the reader sees, so the
  // toggle appears exactly when content is hidden.
  //
  // Both sides of the comparison are content-box heights (the element carries
  // no vertical padding of its own — the space the toggle overlays is reserved
  // by the wrapper), so nothing about the toggle's presence feeds back into
  // the measurement that decides it. The 1px slack absorbs subpixel
  // line-height rounding.
  const checkTextLength = () => {
    nextTick(() => {
      const element = textRef.value;
      // While expanded there is no clamp to overflow, so a measurement would
      // always read "not long" and retract the toggle mid-use. The last
      // clamped measurement stands until the text collapses again.
      if (!element || isExpanded.value) return;

      isLongText.value = element.scrollHeight - element.clientHeight > 1;
    });
  };

  // Coalesce bursts of layout notifications (a resize drag emits one per
  // frame) into a single measurement.
  let pendingFrame: number | null = null;
  const scheduleCheck = () => {
    if (pendingFrame !== null) return;
    pendingFrame = window.requestAnimationFrame(() => {
      pendingFrame = null;
      checkTextLength();
    });
  };

  let resizeObserver: ResizeObserver | null = null;

  onMounted(() => {
    checkTextLength();
    // Re-measure once webfonts finish loading: text measured against the
    // fallback font can sit on the other side of the clamp and render a
    // spurious "Show More" toggle that disappears after the brand font swaps
    // in.
    document.fonts?.ready.then(checkTextLength);

    // Observe the paragraph itself rather than the window: it also catches
    // reflows the window never reports, such as the surrounding layout
    // changing width or the brand font swapping in.
    if (typeof ResizeObserver !== 'undefined' && textRef.value) {
      resizeObserver = new ResizeObserver(scheduleCheck);
      resizeObserver.observe(textRef.value);
    } else {
      window.addEventListener('resize', scheduleCheck);
    }
  });

  onUnmounted(() => {
    resizeObserver?.disconnect();
    window.removeEventListener('resize', scheduleCheck);
    if (pendingFrame !== null) window.cancelAnimationFrame(pendingFrame);
  });

  const toggleExpand = () => {
    isExpanded.value = !isExpanded.value;
    // Collapsing restores the clamp; re-measure in the layout that follows.
    if (!isExpanded.value) checkTextLength();
  };
</script>

<template>
  <div class="min-h-[35vh] w-full rounded-lg bg-white p-4 dark:bg-gray-800 sm:p-6">
    <!-- Title and Instructions -->
    <div class="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
      <slot name="logo"></slot>

      <div class="flex-1 text-center sm:text-left">
        <div class="relative min-h-[5.5rem] sm:min-h-24">
          <h2
            :class="[cornerClass, headingClass]"
            class="mb-2 text-base font-medium leading-normal
              text-gray-900 dark:text-gray-200 sm:mb-3 sm:text-xl">
            <slot name="title">
              {{ defaultTitle }}
            </slot>
          </h2>

          <!-- The bottom padding the toggle overlays lives here, not on the
               paragraph: padding on the measured element would make the
               toggle's presence change the measurement that decides it. -->
          <div
            class="relative"
            :class="isLongText && !isExpanded ? 'pb-6' : 'pb-4'">
            <p
              ref="textRef"
              :class="[textClasses, cornerClass, fontClass]"
              data-testid="brand-instructions">
              {{ instructions || displayComposer.t('web.shared.pre_reveal_default') }}
            </p>

            <button
              v-if="isLongText"
              type="button"
              @click="toggleExpand"
              :aria-expanded="isExpanded"
              data-testid="brand-instructions-toggle"
              :class="[cornerClass, fontClass]"
              class="absolute bottom-0 left-1/2 -translate-x-1/2
                border border-gray-200 bg-white px-3 py-1
                text-xs text-gray-500 shadow-sm transition-all
                duration-200 hover:text-gray-700 hover:shadow
                dark:border-gray-600 dark:bg-gray-800 dark:text-gray-400 dark:hover:text-gray-300">
              <slot
                name="expand-button"
                :is-expanded="isExpanded">
                {{ isExpanded ? displayComposer.t('web.LABELS.view_toggle.show_less') : displayComposer.t('web.LABELS.view_toggle.show_more') }}
              </slot>
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Content Area -->
    <div class="my-3 sm:my-4">
      <div
        :class="[cornerClass]"
        class="flex min-h-32 w-full items-center justify-center
          bg-gray-100 dark:bg-gray-700 sm:min-h-36">
        <slot name="content"></slot>
      </div>
    </div>

    <!-- Action Button -->
    <slot name="action-button"></slot>

    <!-- Footer -->
    <div class="mt-4 flex items-baseline justify-between p-3 sm:p-4">
      <slot name="footer">
        <p class="flex items-center text-xs italic text-gray-400 dark:text-gray-500 sm:text-sm">
          <OIcon
            collection="mdi"
            name="information"
            class="mr-1 size-4" />
          {{ displayComposer.t('web.COMMON.careful_only_see_once') }}
        </p>
      </slot>
    </div>
  </div>
</template>

<style scoped>
  /*
   * The instructions clamp. Scoped so it cannot be redefined from elsewhere in
   * the cascade, and named for its role rather than its line count so callers
   * are not tempted to re-declare a Tailwind utility to change it.
   */
  .instructions-clamp {
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 3;
    line-clamp: 3;
    overflow: hidden;
  }
</style>
