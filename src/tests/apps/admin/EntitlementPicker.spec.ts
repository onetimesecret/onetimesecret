// src/tests/apps/admin/EntitlementPicker.spec.ts

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

import EntitlementPicker from '@/apps/admin/components/organizations/EntitlementPicker.vue';
import type { ColonelAvailableEntitlement } from '@/schemas/api/internal/responses/colonel-organizations';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const CATALOG: ColonelAvailableEntitlement[] = [
  { name: 'api_access', description: 'Can use REST API endpoints', category: 'infrastructure' },
  { name: 'create_secrets', description: 'Can create basic secrets', category: 'core' },
  {
    name: 'custom_domains',
    description: 'Can configure custom domains',
    category: 'infrastructure',
  },
  { name: 'legacy_flag', description: null, category: null },
];

function mountPicker(props: Record<string, unknown> = {}) {
  return mount(EntitlementPicker, {
    props: {
      modelValue: '',
      options: CATALOG,
      plan: ['create_secrets'],
      grants: ['custom_domains'],
      revokes: ['api_access'],
      outOfCatalog: false,
      ...props,
    },
    global: { plugins: [i18n] },
  });
}

describe('EntitlementPicker (catalog dropdown + out-of-catalog escape hatch)', () => {
  it('offers the catalog grouped by category, uncategorized last', () => {
    const wrapper = mountPicker();
    const groups = wrapper.findAll('optgroup');

    expect(groups.map((g) => g.attributes('label'))).toEqual([
      'core',
      'infrastructure',
      'web.admin.organizations.entitlements.picker.uncategorized',
    ]);
  });

  it("annotates options with this org's current state so the pick has context", () => {
    const wrapper = mountPicker();
    const labels = wrapper.findAll('option').map((o) => o.text());

    expect(labels).toContain(
      'create_secrets — web.admin.organizations.entitlements.picker.tags.inPlan'
    );
    expect(labels).toContain(
      'custom_domains — web.admin.organizations.entitlements.picker.tags.granted'
    );
    expect(labels).toContain(
      'api_access — web.admin.organizations.entitlements.picker.tags.revoked'
    );
  });

  it('emits the chosen catalog name and shows its description', async () => {
    const wrapper = mountPicker();
    await wrapper.find('[data-testid="org-entitlement-select"]').setValue('api_access');

    expect(wrapper.emitted('update:modelValue')?.at(-1)).toEqual(['api_access']);

    await wrapper.setProps({ modelValue: 'api_access' });
    expect(wrapper.find('[data-testid="org-entitlement-description"]').text()).toBe(
      'Can use REST API endpoints'
    );
  });

  it('switches to free text on "other" and clears the stale catalog pick', async () => {
    const wrapper = mountPicker({ modelValue: 'api_access' });
    await wrapper.find('[data-testid="org-entitlement-select"]').setValue('__other__');

    // Never carry a catalog pick into the free-text box.
    expect(wrapper.emitted('update:modelValue')?.at(-1)).toEqual(['']);

    await wrapper.setProps({ modelValue: '' });
    expect(wrapper.find('[data-testid="org-entitlement-select"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="org-entitlement-input"]').exists()).toBe(true);

    await wrapper.find('[data-testid="org-entitlement-input"]').setValue('ships_next_release');
    expect(wrapper.emitted('update:modelValue')?.at(-1)).toEqual(['ships_next_release']);
  });

  it('returns to the catalog from the free-text path', async () => {
    const wrapper = mountPicker();
    await wrapper.find('[data-testid="org-entitlement-select"]').setValue('__other__');
    await wrapper.find('[data-testid="org-entitlement-back-to-catalog"]').trigger('click');

    expect(wrapper.find('[data-testid="org-entitlement-select"]').exists()).toBe(true);
  });

  it('shows the CLI warning when the parent says the name is out of catalog', async () => {
    const wrapper = mountPicker({ modelValue: 'ships_next_release', outOfCatalog: true });
    const warning = wrapper.find('[data-testid="org-entitlement-catalog-warning"]');

    expect(warning.exists()).toBe(true);
    expect(warning.text()).toContain('web.admin.organizations.entitlements.catalogWarning');
  });

  it('falls open to free text with no dropdown when the catalog is unavailable', () => {
    const wrapper = mountPicker({ options: [] });

    expect(wrapper.find('[data-testid="org-entitlement-select"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="org-entitlement-input"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="org-entitlement-catalog-unavailable"]').exists()).toBe(true);
    // No way back to a catalog that isn't there.
    expect(wrapper.find('[data-testid="org-entitlement-back-to-catalog"]').exists()).toBe(false);
  });
});
