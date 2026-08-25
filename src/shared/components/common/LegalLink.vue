<!-- src/shared/components/common/LegalLink.vue -->

<script setup lang="ts">
  import { isExternalUrl } from '@/utils/url';
  import { computed, useAttrs } from 'vue';

  /**
   * A link to a legal/policy document whose URL comes from site.legal
   * config (#4278) and may be unset.
   *
   * - Absolute http(s) URL: plain <a> opening in a new tab (noopener).
   * - Relative path: <router-link>, resolved in-app.
   * - Unset (null/empty): the slot renders as plain text — the surrounding
   *   sentence stays grammatical, with no dead anchor. Callers that want
   *   the whole affordance gone instead (e.g. footer entries with
   *   separators) should v-if on the URL themselves.
   *
   * Fallthrough attrs (class, data-testid, aria-label, target, ...) land on
   * the rendered link; the plain-text fallback drops `class` so link
   * styling never dresses up unclickable text.
   */

  defineOptions({ inheritAttrs: false });

  const props = defineProps<{
    url?: string | null;
  }>();

  const attrs = useAttrs();

  const external = computed(() => !!props.url && isExternalUrl(props.url));

  // The unlinked fallback keeps identifying attrs (data-testid, aria-*) but
  // drops link styling and link-only attrs, which have no meaning on a span.
  const textAttrs = computed(() => {
    const { class: _class, target: _target, rel: _rel, ...rest } = attrs;
    return rest;
  });
</script>

<template>
  <a
    v-if="url && external"
    :href="url"
    target="_blank"
    rel="noopener noreferrer"
    v-bind="attrs">
    <slot></slot>
  </a>
  <router-link
    v-else-if="url"
    :to="url"
    v-bind="attrs">
    <slot></slot>
  </router-link>
  <span
    v-else
    v-bind="textAttrs">
    <slot></slot>
  </span>
</template>
