<!-- src/apps/admin/components/organizations/EntitlementPicker.vue -->

<script setup lang="ts">
  import type { ColonelAvailableEntitlement } from '@/schemas/api/internal/responses/colonel-organizations';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Entitlement chooser for the org override controls.
   *
   * PRIMARY affordance is the catalog dropdown: options come from
   * `details.available_entitlements`, which the backend reads from the very
   * same `Billing::Config.load_entitlements` that
   * `EntitlementOverride.known_entitlement?` consults — so what is offered and
   * what the endpoint recognises cannot drift. Options are grouped by category
   * and annotated with this org's current state (in plan / granted / revoked)
   * so the operator picks with context instead of from memory.
   *
   * It is deliberately NOT a pure dropdown. Three CLI paths
   * (`bin/ots org entitlement grant|revoke`, `bin/ots memberships entitlement`)
   * warn-but-ALLOW a name that is not in the catalog, because "granting an
   * entitlement that ships in a later catalog is supported and deliberately not
   * blocked". A dropdown-only console would be a capability regression against
   * the CLI, so the out-of-catalog path stays — behind an explicit choice, and
   * carrying the CLI's own warning wording BEFORE the confirm dialog.
   *
   * When the catalog is unavailable (empty array — billing config missing or
   * unreadable) the component fails OPEN exactly like `known_entitlement?`
   * does: free text becomes the only mode and nothing is flagged as a typo.
   */
  const props = defineProps<{
    /** The chosen entitlement name (v-model). */
    modelValue: string;
    /** The catalog. Empty = unavailable, NOT "nothing is grantable". */
    options: ColonelAvailableEntitlement[];
    /** This org's plan-derived set, for option annotation. */
    plan: string[];
    /** This org's override grants, for option annotation. */
    grants: string[];
    /** This org's override revokes, for option annotation. */
    revokes: string[];
    /**
     * True when the current name is provably absent from a PRESENT catalog.
     * The parent owns this verdict because the confirm dialog repeats it; the
     * component must never re-derive it and risk the two disagreeing.
     */
    outOfCatalog: boolean;
    /** Disable every control (e.g. a mutation is in flight). */
    disabled?: boolean;
  }>();

  const emit = defineEmits<{ 'update:modelValue': [value: string] }>();

  const { t } = useI18n();

  /** Sentinel option value that switches the control to free text. */
  const OTHER = '__other__';

  const catalogAvailable = computed(() => props.options.length > 0);

  /** Operator explicitly asked for the out-of-catalog path. */
  const otherSelected = ref(false);

  const optionNames = computed(() => new Set(props.options.map((option) => option.name)));
  const trimmedValue = computed(() => props.modelValue.trim());

  /**
   * Free text is the only mode without a catalog; otherwise it is opt-in — or
   * forced when the model already holds a name the catalog lacks, so a value
   * the dropdown cannot represent is never invisible to the operator about to
   * confirm it.
   */
  const freeText = computed(() => {
    if (!catalogAvailable.value || otherSelected.value) return true;
    return trimmedValue.value.length > 0 && !optionNames.value.has(trimmedValue.value);
  });

  /** Options grouped by billing.yaml category, categories sorted, blanks last. */
  const groups = computed(() => {
    const byCategory = new Map<string, ColonelAvailableEntitlement[]>();
    props.options.forEach((option) => {
      const key = option.category || '';
      const bucket = byCategory.get(key);
      if (bucket) bucket.push(option);
      else byCategory.set(key, [option]);
    });
    return [...byCategory.entries()]
      .sort(([a], [b]) => {
        if (a === b) return 0;
        if (a === '') return 1;
        if (b === '') return -1;
        return a.localeCompare(b);
      })
      .map(([category, options]) => ({
        key: category || 'uncategorized',
        label: category || t('web.admin.organizations.entitlements.picker.uncategorized'),
        options,
      }));
  });

  /** "custom_domains — in plan, revoked" — the org's state, inline. */
  function optionLabel(option: ColonelAvailableEntitlement): string {
    const tags: string[] = [];
    if (props.plan.includes(option.name)) {
      tags.push(t('web.admin.organizations.entitlements.picker.tags.inPlan'));
    }
    if (props.grants.includes(option.name)) {
      tags.push(t('web.admin.organizations.entitlements.picker.tags.granted'));
    }
    if (props.revokes.includes(option.name)) {
      tags.push(t('web.admin.organizations.entitlements.picker.tags.revoked'));
    }
    return tags.length > 0 ? `${option.name} — ${tags.join(', ')}` : option.name;
  }

  /** Only reflect the model into the select when it IS a catalog entry. */
  const selectValue = computed(() => {
    if (freeText.value) return OTHER;
    return optionNames.value.has(props.modelValue) ? props.modelValue : '';
  });

  const selectedDescription = computed(
    () => props.options.find((option) => option.name === props.modelValue)?.description ?? null
  );

  function onSelect(event: Event): void {
    const value = (event.target as HTMLSelectElement).value;
    if (value === OTHER) {
      // Switching modes clears the name: carrying a catalog pick into the
      // free-text box invites an accidental confirm on a stale value.
      otherSelected.value = true;
      emit('update:modelValue', '');
      return;
    }
    otherSelected.value = false;
    emit('update:modelValue', value);
  }

  function onFreeText(event: Event): void {
    emit('update:modelValue', (event.target as HTMLInputElement).value);
  }

  function backToCatalog(): void {
    otherSelected.value = false;
    emit('update:modelValue', '');
  }
</script>

<template>
  <div>
    <!-- Catalog dropdown: the primary path. -->
    <template v-if="catalogAvailable && !freeText">
      <label
        for="org-entitlement-select"
        class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
        {{ t('web.admin.organizations.entitlements.inputLabel') }}
      </label>
      <select
        id="org-entitlement-select"
        :value="selectValue"
        :disabled="disabled"
        data-testid="org-entitlement-select"
        class="mt-2 w-full rounded-md border border-gray-300 bg-white px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
        @change="onSelect">
        <option value="">
          {{ t('web.admin.organizations.entitlements.picker.selectPlaceholder') }}
        </option>
        <optgroup
          v-for="group in groups"
          :key="group.key"
          :label="group.label">
          <option
            v-for="option in group.options"
            :key="option.name"
            :value="option.name">
            {{ optionLabel(option) }}
          </option>
        </optgroup>
        <option :value="OTHER">
          {{ t('web.admin.organizations.entitlements.picker.other') }}
        </option>
      </select>
      <p
        v-if="selectedDescription"
        class="mt-1 text-xs text-gray-500 dark:text-gray-400"
        data-testid="org-entitlement-description">
        {{ selectedDescription }}
      </p>
    </template>

    <!-- Out-of-catalog path: retained on purpose (CLI parity). -->
    <template v-else>
      <label
        for="org-entitlement-input"
        class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
        {{
          catalogAvailable
            ? t('web.admin.organizations.entitlements.picker.customLabel')
            : t('web.admin.organizations.entitlements.inputLabel')
        }}
      </label>
      <input
        id="org-entitlement-input"
        :value="modelValue"
        type="text"
        autocomplete="off"
        spellcheck="false"
        :disabled="disabled"
        data-testid="org-entitlement-input"
        :placeholder="t('web.admin.organizations.entitlements.placeholder')"
        class="mt-2 w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm placeholder:text-gray-400 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
        @input="onFreeText" />
      <button
        v-if="catalogAvailable"
        type="button"
        class="mt-2 text-xs font-medium text-brand-700 hover:text-brand-800 focus:outline-none dark:text-brand-300 dark:hover:text-brand-200"
        data-testid="org-entitlement-back-to-catalog"
        @click="backToCatalog">
        {{ t('web.admin.organizations.entitlements.picker.backToCatalog') }}
      </button>
      <p
        v-else
        class="mt-1 text-xs text-gray-500 dark:text-gray-400"
        data-testid="org-entitlement-catalog-unavailable">
        {{ t('web.admin.organizations.entitlements.picker.catalogUnavailable') }}
      </p>
    </template>

    <!-- The CLI's warning, verbatim in substance, BEFORE the confirm dialog. -->
    <p
      v-if="outOfCatalog"
      class="mt-2 flex items-start gap-1.5 rounded-md border border-amber-300 bg-amber-50 p-2 text-xs text-amber-800 dark:border-amber-900/50 dark:bg-amber-900/20 dark:text-amber-200"
      role="status"
      data-testid="org-entitlement-catalog-warning">
      <OIcon
        collection="heroicons"
        name="exclamation-triangle"
        size="4"
        class="mt-px shrink-0" />
      <span>{{
        t('web.admin.organizations.entitlements.catalogWarning', { entitlement: modelValue.trim() })
      }}</span>
    </p>
  </div>
</template>
