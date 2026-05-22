// src/tests/components/ShowReceiptCapabilities.spec.ts

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';
import ShowReceipt from '@/apps/secret/reveal/ShowReceipt.vue';
import BurnButtonForm from '@/apps/secret/components/receipt/BurnButtonForm.vue';

// Default record/details represent an available (not destroyed/burned/revealed)
// receipt so that `isAvailable` is true and the Burn action section can render.
// Tests that need an unavailable receipt override the record before mounting.
const recordRef = ref<Record<string, unknown> | null>(null);
const detailsRef = ref<Record<string, unknown> | null>(null);

vi.mock('@/shared/composables/useReceipt', () => ({
  useReceipt: vi.fn(() => ({
    record: recordRef,
    details: detailsRef,
    isLoading: ref(false),
    passphrase: ref(''),
    error: ref(null),
    canBurn: ref(true),
    fetch: vi.fn(),
    burn: vi.fn(),
    reset: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/useSecretExpiration', () => ({
  useSecretExpiration: vi.fn(() => ({
    onExpirationEvent: vi.fn(),
  })),
  EXPIRATION_EVENTS: { EXPIRED: 'expired', WARNING: 'warning' },
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

const availableRecord = () => ({
  key: 'testkey',
  is_destroyed: false,
  is_burned: false,
  is_revealed: false,
  is_previewed: false,
});

const burnedRecord = () => ({
  ...availableRecord(),
  is_burned: true,
});

const baseDetails = () => ({
  show_secret: false,
  secret_value: null,
  show_recipients: false,
  has_passphrase: false,
});

const mountReceipt = (
  burnCapability: boolean | undefined,
  record: Record<string, unknown> = availableRecord()
) => {
  recordRef.value = record;
  detailsRef.value = baseDetails();

  const capabilities =
    burnCapability === undefined ? {} : { burn: burnCapability };

  return mount(ShowReceipt, {
    props: { receiptIdentifier: 'testkey' },
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            bootstrap: {
              ui: { capabilities },
            },
          },
        }),
      ],
      // Stub child components: BurnButtonForm is kept stubbed (not deep-rendered)
      // so the test asserts on the gated section rather than the child's own
      // internals (which call useReceipt and run timers).
      stubs: {
        BurnButtonForm: true,
        SecretLink: true,
        StatusBadge: true,
        TimelineDisplay: true,
        ReceiptFAQ: true,
        NeedHelpModal: true,
        OIcon: true,
        ReceiptSkeleton: true,
        UnknownReceipt: true,
        CopyButton: true,
      },
    },
  });
};

describe('ShowReceipt - burn capability gating', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('hides the Burn action when ui.capabilities.burn is false', () => {
    const wrapper = mountReceipt(false);
    expect(wrapper.findComponent(BurnButtonForm).exists()).toBe(false);
  });

  it('shows the Burn action when ui.capabilities.burn is true', () => {
    const wrapper = mountReceipt(true);
    expect(wrapper.findComponent(BurnButtonForm).exists()).toBe(true);
  });

  it('shows the Burn action when the capability flag is unset (default enabled)', () => {
    const wrapper = mountReceipt(undefined);
    expect(wrapper.findComponent(BurnButtonForm).exists()).toBe(true);
  });

  it('keeps the Burn action hidden for an unavailable receipt regardless of capability', () => {
    const wrapper = mountReceipt(true, burnedRecord());
    expect(wrapper.findComponent(BurnButtonForm).exists()).toBe(false);
  });
});
