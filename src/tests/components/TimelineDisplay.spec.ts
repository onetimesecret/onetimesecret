// src/tests/components/TimelineDisplay.spec.ts
//
// Component specs for #3829: the receipt TimelineDisplay must render a
// "Previewed" event row (gated on record.is_previewed) between Created and
// Received, without disturbing the Received/Burned/Expiration sections.

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';
import TimelineDisplay from '@/apps/secret/components/receipt/TimelineDisplay.vue';
import type { Receipt, ReceiptDetails } from '@/schemas/shapes/v3/receipt';
import { mockReceiptRecord, mockReceiptDetails } from '../fixtures/receipt.fixture';

// Lazy closures: refs are only dereferenced when the composable is called
// at mount time (same pattern as ShowReceiptCapabilities.spec.ts).
const expirationStateRef = ref<'active' | 'warning' | 'expired'>('active');

vi.mock('@/shared/composables/useSecretExpiration', () => ({
  useSecretExpiration: vi.fn(() => ({
    progress: ref(42),
    timeRemaining: ref('12 hours'),
    expirationDate: ref(new Date('2025-01-01T00:00:00.000Z')),
    expirationState: expirationStateRef,
    onExpirationEvent: vi.fn(),
  })),
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

const CREATED_AT = new Date(1735142814 * 1000);
const PREVIEWED_AT = new Date(1735146414 * 1000);
const REVEALED_AT = new Date(1735150014 * 1000);

/**
 * Build a parsed-shape (v3) receipt record. Base fixture is the parsed
 * mockReceiptRecord (Dates, canonical booleans, is_previewed/is_revealed
 * false); overrides are plain values cast to the shape type.
 */
const makeRecord = (overrides: Record<string, unknown> = {}): Receipt =>
  ({
    ...mockReceiptRecord,
    created: CREATED_AT,
    ...overrides,
  }) as unknown as Receipt;

const mountTimeline = (record: Receipt) =>
  mount(TimelineDisplay, {
    props: {
      record,
      details: mockReceiptDetails as unknown as ReceiptDetails,
    },
    global: {
      stubs: { OIcon: true },
    },
  });

// Event label paragraphs, in DOM order (created / previewed / received /
// burned / expiration all use `p.font-brand` for their title).
const eventLabels = (wrapper: ReturnType<typeof mountTimeline>) =>
  wrapper.findAll('p.font-brand').map((p) => p.text().trim());

describe('TimelineDisplay — #3829 previewed event row', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    expirationStateRef.value = 'active';
  });

  it('renders no Previewed row when is_previewed is false', () => {
    const wrapper = mountTimeline(makeRecord({ is_previewed: false }));

    expect(wrapper.text()).not.toContain('web.STATUS.previewed');
    // No blue previewed icon circle either.
    expect(wrapper.find('.bg-blue-100').exists()).toBe(false);
    expect(wrapper.text()).toContain('web.STATUS.created');
  });

  it('renders the Previewed row with timestamp for a previewed, unrevealed receipt', () => {
    const wrapper = mountTimeline(
      makeRecord({
        state: 'previewed',
        is_previewed: true,
        previewed: PREVIEWED_AT,
      })
    );

    expect(wrapper.text()).toContain('web.STATUS.previewed');
    expect(wrapper.text()).toContain('web.STATUS.created');
    // Not revealed: no Received row.
    expect(wrapper.text()).not.toContain('web.STATUS.received');
    // Expiration section still rendered (not burned, not revealed).
    expect(wrapper.text()).toContain('web.STATUS.expires');

    // <time> elements in DOM order: Created, Previewed, Expiration.
    const times = wrapper.findAll('time');
    expect(times).toHaveLength(3);
    expect(times[0].attributes('datetime')).toBe(CREATED_AT.toISOString());
    expect(times[1].attributes('datetime')).toBe(PREVIEWED_AT.toISOString());
  });

  it('renders BOTH Previewed and Received rows for a previewed then revealed receipt', () => {
    const wrapper = mountTimeline(
      makeRecord({
        state: 'revealed',
        is_previewed: true,
        previewed: PREVIEWED_AT,
        is_revealed: true,
        revealed: REVEALED_AT,
      })
    );

    expect(wrapper.text()).toContain('web.STATUS.previewed');
    expect(wrapper.text()).toContain('web.STATUS.received');
    // showExpiration is false once revealed: no expires/expired label.
    expect(wrapper.text()).not.toContain('web.STATUS.expire');

    // <time> elements in DOM order: Created, Previewed, Received.
    const times = wrapper.findAll('time');
    expect(times).toHaveLength(3);
    expect(times[1].attributes('datetime')).toBe(PREVIEWED_AT.toISOString());
    expect(times[2].attributes('datetime')).toBe(REVEALED_AT.toISOString());
  });

  it('renders defensively when is_previewed is true but previewed timestamp is null', () => {
    const wrapper = mountTimeline(makeRecord({ is_previewed: true, previewed: null }));

    // Row renders (gated on the boolean only) without crashing.
    expect(wrapper.text()).toContain('web.STATUS.previewed');
    // Previewed <time> is second (after Created): empty text, no datetime attr.
    const previewedTime = wrapper.findAll('time')[1];
    expect(previewedTime.text().trim()).toBe('');
    expect(previewedTime.attributes('datetime')).toBeUndefined();
  });

  it('orders the Previewed row after Created and before Received', () => {
    const wrapper = mountTimeline(
      makeRecord({
        state: 'revealed',
        is_previewed: true,
        previewed: PREVIEWED_AT,
        is_revealed: true,
        revealed: REVEALED_AT,
      })
    );

    expect(eventLabels(wrapper)).toEqual([
      'web.STATUS.created',
      'web.STATUS.previewed',
      'web.STATUS.received',
    ]);
  });
});
