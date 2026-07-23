// src/tests/components/StatusBadge.spec.ts
//
// Component specs for #3829: the receipt StatusBadge must surface the
// is_previewed telemetry (#3633) as a 'previewed' display state without
// disturbing terminal states, legacy states, or time-based overrides.
//
// Precedence under test (StatusBadge `status` computed):
//   1. composable expirationState 'expired'/'warning'  (highest)
//   2. getDisplayStatus(state, expiresIn) — 'expiring_soon' when state is
//      NEW and server-authoritative expiresIn < 1800
//   3. is_previewed override — only when the display status is 'new'
//   4. STATE_TO_DISPLAY mapping (terminal + legacy states pass through)

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';
import StatusBadge from '@/apps/secret/components/receipt/StatusBadge.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import type { Receipt } from '@/schemas/shapes/v3/receipt';
import { mockReceiptRecord } from '../fixtures/receipt.fixture';

// Configurable expiration state so tests can drive the composable-derived
// branches ('expired' / 'warning') independently of the record contents.
// Lazy closure: the ref is only dereferenced when the composable is called
// at mount time (same pattern as ShowReceiptCapabilities.spec.ts).
const expirationStateRef = ref<'active' | 'warning' | 'expired'>('active');

vi.mock('@/shared/composables/useSecretExpiration', () => ({
  useSecretExpiration: vi.fn(() => ({
    expirationState: expirationStateRef,
  })),
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

const PREVIEWED_AT = new Date(1735142814 * 1000);

/**
 * Build a parsed-shape (v3) receipt record. Base fixture is the parsed
 * mockReceiptRecord (Dates, canonical booleans); overrides are plain values
 * cast to the shape type, matching existing component-spec conventions.
 */
const makeRecord = (overrides: Record<string, unknown> = {}): Receipt =>
  ({
    ...mockReceiptRecord,
    secret_state: null,
    ...overrides,
  }) as unknown as Receipt;

const mountBadge = (record: Receipt, expiresIn?: number) =>
  mount(StatusBadge, {
    props: expiresIn === undefined ? { record } : { record, expiresIn },
    global: {
      stubs: { OIcon: true },
    },
  });

describe('StatusBadge — #3829 previewed display state', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    expirationStateRef.value = 'active';
  });

  it('shows New for a never-accessed receipt (state new, is_previewed false)', () => {
    const wrapper = mountBadge(makeRecord({ state: 'new', is_previewed: false }));
    expect(wrapper.text().trim()).toBe('web.STATUS.new');
  });

  it('shows Previewed when a new receipt has been previewed (no expiresIn prop)', () => {
    // expiresIn deliberately omitted: the prop is optional and the override
    // must not depend on it being present.
    const wrapper = mountBadge(
      makeRecord({ state: 'new', is_previewed: true, previewed: PREVIEWED_AT })
    );
    expect(wrapper.text().trim()).toBe('web.STATUS.previewed');

    // Pin the previewed branch: blue styling, unread-mail icon, description tooltip.
    const badge = wrapper.find('[role="status"]');
    expect(badge.classes()).toContain('text-blue-800');
    expect(badge.attributes('title')).toBe('web.STATUS.previewed_description');
    expect(wrapper.findComponent(OIcon).attributes('name')).toBe('mark-email-unread-outline');
  });

  it('terminal revealed state wins over is_previewed', () => {
    const wrapper = mountBadge(
      makeRecord({
        state: 'revealed',
        is_previewed: true,
        is_revealed: true,
        previewed: PREVIEWED_AT,
      })
    );
    expect(wrapper.text().trim()).toBe('web.STATUS.revealed');
  });

  it('terminal burned state wins over is_previewed', () => {
    const wrapper = mountBadge(
      makeRecord({
        state: 'burned',
        is_previewed: true,
        is_burned: true,
        previewed: PREVIEWED_AT,
      })
    );
    expect(wrapper.text().trim()).toBe('web.STATUS.burned');
  });

  it('legacy record with state previewed displays Previewed regardless of is_previewed', () => {
    // The label comes from STATE_TO_DISPLAY, not from the is_previewed
    // override, so it must hold even with is_previewed false.
    const wrapper = mountBadge(makeRecord({ state: 'previewed', is_previewed: false }));
    expect(wrapper.text().trim()).toBe('web.STATUS.previewed');
  });

  it('renders legacy viewed state as Previewed (tolerant display layer, #3829)', () => {
    // #3829 root fix: the badge routes state through getDisplayStatus — the
    // single display authority, built on the v2-tolerant layer — instead of
    // pre-validating against the strict v3 schema. Legacy aliases degrade to
    // their canonical display state (viewed -> previewed) rather than throwing.
    // The label comes from STATE_TO_DISPLAY, not the is_previewed override, so
    // it holds even with is_previewed false.
    const wrapper = mountBadge(makeRecord({ state: 'viewed', is_previewed: false }));
    expect(wrapper.text().trim()).toBe('web.STATUS.previewed');
  });

  it('renders legacy received state as Revealed (tolerant display layer, #3829)', () => {
    const wrapper = mountBadge(makeRecord({ state: 'received', is_previewed: false }));
    expect(wrapper.text().trim()).toBe('web.STATUS.revealed');
  });

  it('degrades an unrecognized state to Orphaned instead of throwing (#3829)', () => {
    // The trap is fully closed: no state string can crash the badge. An
    // unknown value falls through getDisplayStatus's guard to 'orphaned'.
    const wrapper = mountBadge(makeRecord({ state: 'bogus', is_previewed: false }));
    expect(wrapper.text().trim()).toBe('web.STATUS.orphaned');
  });

  it('server-authoritative expiring-soon (expiresIn < 1800) outranks previewed', () => {
    const wrapper = mountBadge(
      makeRecord({ state: 'new', is_previewed: true, previewed: PREVIEWED_AT }),
      900
    );
    expect(wrapper.text().trim()).toBe('web.STATUS.expiring_soon');
  });

  it('expiresIn >= 1800 leaves the previewed override in place', () => {
    const wrapper = mountBadge(
      makeRecord({ state: 'new', is_previewed: true, previewed: PREVIEWED_AT }),
      3600
    );
    expect(wrapper.text().trim()).toBe('web.STATUS.previewed');
  });

  it('composable expired state wins regardless of is_previewed', () => {
    expirationStateRef.value = 'expired';
    const wrapper = mountBadge(
      makeRecord({ state: 'new', is_previewed: true, previewed: PREVIEWED_AT })
    );
    expect(wrapper.text().trim()).toBe('web.STATUS.expired');
  });
});
