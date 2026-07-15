<!-- src/apps/admin/components/kit/JsonViewerNode.vue -->

<script setup lang="ts">
  import { computed, ref, watch } from 'vue';

  import OIcon from '@/shared/components/icons/OIcon.vue';

  import type { JsonViewerSignal } from './jsonViewerKeys';

  /**
   * Recursive rendering node for {@link JsonViewer}. Not a public kit component —
   * it is an internal detail co-located with its only consumer.
   *
   * Each container node (object/array) owns its collapsed state locally, but also
   * reacts to the `signal` prop the toolbar bumps, so "expand all" /
   * "collapse all" propagate through the whole tree while leaving per-node
   * toggling intact afterwards. Config is threaded by props (see
   * {@link JsonViewerSignal}) rather than provide/inject.
   */
  const props = defineProps<{
    /** The value at this node. */
    value: unknown;
    /** The object key or array index label to prefix (omitted at the root). */
    keyLabel?: string;
    /** Nesting depth (root = 0). Drives the initial expanded state. */
    depth: number;
    /** Depth (exclusive) below which container nodes start expanded. */
    expandDepth: number;
    /** Toolbar expand/collapse broadcast (shared object reference). */
    signal: JsonViewerSignal;
  }>();

  type ValueKind = 'object' | 'array' | 'string' | 'number' | 'boolean' | 'null';

  const kind = computed<ValueKind>(() => {
    const v = props.value;
    if (v === null || v === undefined) return 'null';
    if (Array.isArray(v)) return 'array';
    switch (typeof v) {
      case 'object':
        return 'object';
      case 'number':
        return 'number';
      case 'boolean':
        return 'boolean';
      default:
        return 'string';
    }
  });

  const isContainer = computed(() => kind.value === 'object' || kind.value === 'array');

  const entries = computed<Array<[string, unknown]>>(() => {
    if (kind.value === 'array') {
      return (props.value as unknown[]).map((v, i) => [String(i), v]);
    }
    if (kind.value === 'object') {
      return Object.entries(props.value as Record<string, unknown>);
    }
    return [];
  });

  const isEmptyContainer = computed(() => isContainer.value && entries.value.length === 0);

  /** Collapsed preview, e.g. `{ 3 }` / `[ 2 ]`. */
  const summary = computed(() => {
    const count = entries.value.length;
    return kind.value === 'array' ? `[ ${count} ]` : `{ ${count} }`;
  });

  // Initial collapsed state comes from `expandDepth`, EXCEPT when a toolbar
  // expand-all / collapse-all has already been broadcast (`version > 0`). A
  // deeper container mounts only after its parent expands, which for an
  // in-progress expand-all happens AFTER the version bump — so it would miss
  // the watcher below and re-initialise from `expandDepth`, stalling the
  // cascade one level past what was already visible. Seeding from the latest
  // broadcast lets freshly-mounted descendants inherit it.
  const expanded = ref(
    props.signal.version > 0 ? props.signal.expanded : props.depth < props.expandDepth
  );

  // React to toolbar expand-all / collapse-all.
  watch(
    () => props.signal.version,
    () => {
      if (isContainer.value) expanded.value = props.signal.expanded;
    }
  );

  function toggle(): void {
    expanded.value = !expanded.value;
  }

  const primitiveClass = computed(() => {
    switch (kind.value) {
      case 'string':
        return 'text-green-700 dark:text-green-400';
      case 'number':
        return 'text-blue-700 dark:text-blue-400';
      case 'boolean':
        return 'text-purple-700 dark:text-purple-400';
      case 'null':
        return 'text-gray-400 dark:text-gray-500';
      default:
        return '';
    }
  });

  const primitiveText = computed(() => {
    if (kind.value === 'string') return JSON.stringify(props.value);
    if (kind.value === 'null') return 'null';
    return String(props.value);
  });
</script>

<template>
  <div class="leading-6">
    <!-- Container: object / array -->
    <template v-if="isContainer">
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded hover:bg-gray-100 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:hover:bg-gray-800"
        :aria-expanded="expanded"
        @click="toggle">
        <OIcon
          collection="heroicons"
          :name="expanded ? 'chevron-down' : 'chevron-right'"
          size="4"
          class="text-gray-400 dark:text-gray-500" />
        <span
          v-if="keyLabel !== undefined"
          class="text-gray-700 dark:text-gray-300">{{ keyLabel }}:</span>
        <span class="text-gray-400 dark:text-gray-500">{{ summary }}</span>
      </button>

      <div
        v-if="expanded && !isEmptyContainer"
        class="border-l border-gray-200 pl-4 dark:border-gray-700">
        <JsonViewerNode
          v-for="[childKey, childValue] in entries"
          :key="childKey"
          :value="childValue"
          :key-label="childKey"
          :depth="depth + 1"
          :expand-depth="expandDepth"
          :signal="signal" />
      </div>
    </template>

    <!-- Primitive -->
    <div
      v-else
      class="flex items-baseline gap-1">
      <span
        v-if="keyLabel !== undefined"
        class="text-gray-700 dark:text-gray-300">{{ keyLabel }}:</span>
      <span :class="primitiveClass">{{ primitiveText }}</span>
    </div>
  </div>
</template>
