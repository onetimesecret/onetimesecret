<!-- src/apps/workspace/components/domains/DomainHomepageNetworkAccess.vue -->

<script setup lang="ts">
  /**
   * Domain Homepage Network Access
   *
   * Editor for the two per-domain homepage network rules: the networks
   * allowed to use the interactive homepage and the networks denied it.
   * Both lists hold IPv4/IPv6 addresses or CIDR ranges. Empty lists mean no
   * restriction; a denied range always wins over the allowed list. Visitors
   * refused by network get the private landing page (and a 403 from
   * anonymous secret creation), exactly like a disabled homepage, so the
   * rule itself is never advertised.
   *
   * Unlike the experience selector, which saves on selection, this editor
   * is explicit: entries are staged locally and written with Save, because
   * one list typically changes several entries at a time. The server
   * normalizes entries ("address/prefix", de-duplicated) and rejects
   * anything unparseable, naming the entry — the client check below is a
   * shape hint for typos, not the validator.
   *
   * Signed-in members and the management pages are never gated by these
   * rules, so an operator cannot lock themselves out of fixing a list.
   */
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';

  export interface HomepageNetworkRules {
    allowed_cidrs: string[];
    denied_cidrs: string[];
  }

  type ListKey = 'allowed' | 'denied';

  interface Props {
    /** Stored allowed ranges (normalized by the server). */
    allowedCidrs: string[];
    /** Stored denied ranges (normalized by the server). */
    deniedCidrs: string[];
    /** Disable all controls (loading, insufficient role, another save in flight). */
    disabled?: boolean;
    /** A save of these rules is in flight. */
    saving?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    disabled: false,
    saving: false,
  });

  const emit = defineEmits<{
    (e: 'save', rules: HomepageNetworkRules): void;
    /** Staged edits exist (or no longer do); the parent guards navigation on it. */
    (e: 'update:dirty', dirty: boolean): void;
  }>();

  const { t } = useI18n();

  const sameList = (a: string[], b: string[]) =>
    a.length === b.length && a.every((item, i) => item === b[i]);

  // Staged copies of the stored lists. A record refresh re-seeds a list
  // only when it holds no staged edits, or when the refresh is this
  // editor's own save landing (the parent keeps `saving` set until its
  // post-save refetch is in, and the server returns normalized entries).
  // An unrelated refresh, such as the experience selector's save, keeps
  // the operator's staged edits.
  const allowed = ref<string[]>([...props.allowedCidrs]);
  const denied = ref<string[]>([...props.deniedCidrs]);

  watch(
    () => props.allowedCidrs,
    (next, prev) => {
      if (props.saving || sameList(allowed.value, prev)) allowed.value = [...next];
    }
  );
  watch(
    () => props.deniedCidrs,
    (next, prev) => {
      if (props.saving || sameList(denied.value, prev)) denied.value = [...next];
    }
  );

  const drafts = ref<Record<ListKey, string>>({ allowed: '', denied: '' });
  const errors = ref<Record<ListKey, string>>({ allowed: '', denied: '' });

  const listRef = (key: ListKey) => (key === 'allowed' ? allowed : denied);

  // Shape hint only: hex digits, dots and colons with an optional /prefix.
  // The server (IPAddr) is authoritative and its 422 names the refused entry.
  const CIDR_SHAPE = /^[0-9a-fA-F:.]+(\/\d{1,3})?$/;

  const addEntry = (key: ListKey) => {
    const entry = drafts.value[key].trim();
    if (!entry) return;

    if (!CIDR_SHAPE.test(entry)) {
      errors.value[key] = t('web.domains.homepage.network_invalid_entry');
      return;
    }
    const list = listRef(key);
    if (list.value.includes(entry)) {
      errors.value[key] = t('web.domains.homepage.network_entry_exists');
      return;
    }

    list.value = [...list.value, entry];
    drafts.value[key] = '';
    errors.value[key] = '';
  };

  const removeEntry = (key: ListKey, entry: string) => {
    const list = listRef(key);
    list.value = list.value.filter((item) => item !== entry);
  };

  // Typing clears the inline error for that list.
  watch(
    () => drafts.value.allowed,
    () => {
      errors.value.allowed = '';
    }
  );
  watch(
    () => drafts.value.denied,
    () => {
      errors.value.denied = '';
    }
  );

  const isDirty = computed(
    () => !sameList(allowed.value, props.allowedCidrs) || !sameList(denied.value, props.deniedCidrs)
  );

  watch(isDirty, (dirty) => emit('update:dirty', dirty));

  const restricted = computed(() => allowed.value.length > 0 || denied.value.length > 0);

  const save = () => {
    if (!isDirty.value || props.disabled || props.saving) return;
    emit('save', { allowed_cidrs: allowed.value, denied_cidrs: denied.value });
  };

  const discard = () => {
    allowed.value = [...props.allowedCidrs];
    denied.value = [...props.deniedCidrs];
    drafts.value = { allowed: '', denied: '' };
    errors.value = { allowed: '', denied: '' };
  };

  interface ListDescriptor {
    key: ListKey;
    labelKey: string;
    hintKey: string;
    testId: string;
  }

  const lists: readonly ListDescriptor[] = [
    {
      key: 'allowed',
      labelKey: 'web.domains.homepage.network_allowed_label',
      hintKey: 'web.domains.homepage.network_allowed_hint',
      testId: 'homepage-network-allowed',
    },
    {
      key: 'denied',
      labelKey: 'web.domains.homepage.network_denied_label',
      hintKey: 'web.domains.homepage.network_denied_hint',
      testId: 'homepage-network-denied',
    },
  ];
</script>

<template>
  <div data-testid="homepage-network-access">
    <div class="flex items-start gap-2">
      <OIcon
        collection="heroicons"
        name="globe-alt"
        class="mt-0.5 size-4 shrink-0 text-gray-500 dark:text-gray-400"
        aria-hidden="true" />
      <div class="min-w-0">
        <h4 class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.homepage.network_title') }}
        </h4>
        <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
          {{ t('web.domains.homepage.network_description') }}
        </p>
      </div>
    </div>

    <div class="mt-4 space-y-5">
      <div
        v-for="list in lists"
        :key="list.key"
        :data-testid="list.testId">
        <label
          :for="`homepage-network-${list.key}-input`"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t(list.labelKey) }}
        </label>
        <p
          :id="`homepage-network-${list.key}-hint`"
          class="mt-1 text-xs text-gray-500 dark:text-gray-400">
          {{ t(list.hintKey) }}
        </p>

        <!-- Entry chips -->
        <div
          v-if="listRef(list.key).value.length > 0"
          class="mt-2 flex flex-wrap gap-2"
          role="list"
          :aria-label="t(list.labelKey)">
          <span
            v-for="entry in listRef(list.key).value"
            :key="entry"
            role="listitem"
            class="inline-flex items-center gap-1 rounded-full bg-gray-100 px-3 py-1 font-mono text-xs text-gray-700 dark:bg-gray-600 dark:text-gray-200">
            {{ entry }}
            <button
              type="button"
              :disabled="disabled || saving"
              class="ml-1 rounded-full p-0.5 text-gray-400 hover:bg-gray-200 hover:text-gray-600 disabled:cursor-not-allowed disabled:opacity-50 dark:hover:bg-gray-500 dark:hover:text-gray-100"
              :aria-label="t('web.domains.homepage.network_remove_entry', { cidr: entry })"
              @click="removeEntry(list.key, entry)">
              <OIcon
                collection="heroicons"
                name="x-mark"
                class="size-3.5"
                aria-hidden="true" />
            </button>
          </span>
        </div>

        <!-- Add entry -->
        <div class="mt-2 flex gap-2">
          <div class="flex-1">
            <input
              :id="`homepage-network-${list.key}-input`"
              v-model="drafts[list.key]"
              type="text"
              inputmode="text"
              autocomplete="off"
              autocapitalize="off"
              autocorrect="off"
              spellcheck="false"
              :disabled="disabled || saving"
              :placeholder="t('web.domains.homepage.network_entry_placeholder')"
              :aria-describedby="`homepage-network-${list.key}-hint homepage-network-${list.key}-error`"
              :aria-invalid="!!errors[list.key]"
              class="block w-full rounded-md border-gray-300 font-mono shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400"
              @keydown.enter.prevent="addEntry(list.key)" />
          </div>
          <button
            type="button"
            :disabled="disabled || saving"
            class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600"
            @click="addEntry(list.key)">
            {{ t('web.COMMON.add') }}
          </button>
        </div>
        <p
          :id="`homepage-network-${list.key}-error`"
          class="mt-1 min-h-4 text-xs text-red-600 dark:text-red-400"
          role="alert">
          {{ errors[list.key] }}
        </p>
      </div>
    </div>

    <div class="mt-3 flex flex-wrap items-center justify-between gap-3">
      <p class="text-xs text-gray-500 dark:text-gray-400">
        <template v-if="restricted">
          {{ t('web.domains.homepage.network_management_note') }}
        </template>
        <template v-else>
          {{ t('web.domains.homepage.network_open_note') }}
        </template>
      </p>
      <div
        v-if="isDirty"
        class="flex items-center gap-2">
        <button
          type="button"
          :disabled="disabled || saving"
          class="rounded-md px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-300 dark:hover:bg-gray-700"
          data-testid="homepage-network-discard"
          @click="discard">
          {{ t('web.domains.homepage.network_discard') }}
        </button>
        <button
          type="button"
          :disabled="disabled || saving"
          class="inline-flex items-center rounded-md bg-brand-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 disabled:cursor-not-allowed disabled:opacity-50"
          data-testid="homepage-network-save"
          @click="save">
          {{
            saving
              ? t('web.domains.homepage.network_saving')
              : t('web.domains.homepage.network_save')
          }}
        </button>
      </div>
    </div>
  </div>
</template>
