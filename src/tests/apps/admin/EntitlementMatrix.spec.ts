// src/tests/apps/admin/EntitlementMatrix.spec.ts

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/utils/format', () => ({
  formatDisplayDateTime: (d: Date) => `DT:${d.toISOString()}`,
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

import EntitlementMatrix from '@/apps/admin/components/organizations/EntitlementMatrix.vue';
import type { ColonelOrganizationDetailEntitlements } from '@/schemas/api/internal/responses/colonel-organizations';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

function entitlements(
  overrides: Partial<ColonelOrganizationDetailEntitlements> = {}
): ColonelOrganizationDetailEntitlements {
  return {
    plan: ['api_access', 'create_secrets'],
    grants: ['custom_domains'],
    revokes: ['api_access'],
    materialized: ['create_secrets', 'custom_domains'],
    expected: ['create_secrets', 'custom_domains'],
    materialized_flag: true,
    materialized_at: new Date('2026-07-01T00:00:00.000Z'),
    plan_stale: false,
    drift: { extra: [], missing: [], in_sync: true },
    ...overrides,
  };
}

const mountMatrix = (value = entitlements()) =>
  mount(EntitlementMatrix, {
    props: { entitlements: value },
    global: { plugins: [i18n] },
  });

describe('EntitlementMatrix (org entitlement resolution matrix)', () => {
  it('renders one row per entitlement across the union of every source set', () => {
    const wrapper = mountMatrix();

    // plan ∪ grants ∪ revokes ∪ materialized, sorted.
    const names = wrapper
      .findAll('tbody tr')
      .map((row) => row.find('th[scope="row"]').text());
    expect(names).toEqual(['api_access', 'create_secrets', 'custom_domains']);
  });

  it('marks each source column with accessible text, not colour alone', () => {
    const wrapper = mountMatrix();
    const row = wrapper.find('[data-testid="entitlement-row-create_secrets"]');
    const cells = row.findAll('td');

    // inPlan / granted / revoked / expected / materialized + state = 6 cells.
    expect(cells).toHaveLength(6);
    // In plan: ✓ with an sr-only "yes"; granted: — with an sr-only "no".
    expect(cells[0].text()).toContain('web.admin.organizations.entitlements.matrix.yes');
    expect(cells[1].text()).toContain('web.admin.organizations.entitlements.matrix.no');
    expect(cells[0].find('span[aria-hidden="true"]').text()).toBe('✓');
  });

  it('classifies each row so the operator reads WHY it resolves that way', () => {
    const wrapper = mountMatrix();

    // Revoked by an admin override — struck through, and named as such.
    const revoked = wrapper.find('[data-testid="entitlement-row-api_access"]');
    expect(revoked.attributes('data-state')).toBe('revoked');
    expect(revoked.find('th[scope="row"]').classes()).toContain('line-through');

    expect(
      wrapper.find('[data-testid="entitlement-row-create_secrets"]').attributes('data-state')
    ).toBe('plan');
    expect(
      wrapper.find('[data-testid="entitlement-row-custom_domains"]').attributes('data-state')
    ).toBe('granted');
  });

  it('flags drift rows: orphaned (materialized, not expected) and missing (expected, not materialized)', () => {
    const wrapper = mountMatrix(
      entitlements({
        materialized: ['create_secrets', 'legacy_flag'],
        drift: { extra: ['legacy_flag'], missing: ['custom_domains'], in_sync: false },
      })
    );

    expect(wrapper.find('[data-testid="entitlement-row-legacy_flag"]').attributes('data-state')).toBe(
      'orphaned'
    );
    expect(
      wrapper.find('[data-testid="entitlement-row-custom_domains"]').attributes('data-state')
    ).toBe('missing');
    // Both get the warning wash, and the summary call-out is present.
    expect(wrapper.find('[data-testid="entitlement-row-legacy_flag"]').classes()).toContain(
      'bg-amber-50'
    );
    expect(wrapper.find('[data-testid="entitlements-drift"]').exists()).toBe(true);
  });

  it('renders plan_stale === null as unknown, never as in-sync', () => {
    const wrapper = mountMatrix(entitlements({ plan_stale: null }));
    const cell = wrapper.find('[data-testid="entitlements-summary-plan-stale"]');
    expect(cell.text()).toContain('web.admin.organizations.entitlements.summary.planUnknown');
    expect(cell.text()).not.toContain('summary.planCurrent');
  });

  it('reports a never-materialized org (flag false, no timestamp) in the summary', () => {
    const wrapper = mountMatrix(
      entitlements({ materialized_flag: false, materialized_at: null, materialized: [] })
    );
    expect(wrapper.find('[data-testid="entitlements-summary-materialized"]').text()).toContain(
      'web.admin.organizations.entitlements.summary.no'
    );
    expect(wrapper.find('[data-testid="entitlements-summary-materialized-at"]').text()).toContain(
      'web.admin.organizations.entitlements.summary.never'
    );
  });

  it('keeps the wide table inside its own horizontal scroll container', () => {
    const wrapper = mountMatrix();
    const scroller = wrapper.find('[data-testid="entitlements-matrix-scroll"]');
    expect(scroller.classes()).toContain('overflow-x-auto');
    expect(scroller.find('table').classes()).toContain('min-w-full');
  });

  it('renders an empty state when the org resolves to no entitlements at all', () => {
    const wrapper = mountMatrix(
      entitlements({
        plan: [],
        grants: [],
        revokes: [],
        materialized: [],
        expected: [],
      })
    );
    expect(wrapper.find('[data-testid="entitlements-matrix-empty"]').exists()).toBe(true);
  });
});
