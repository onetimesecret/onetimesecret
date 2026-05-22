// src/tests/components/WorkspaceSecretFormCapabilities.spec.ts

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';
import WorkspaceSecretForm from '@/apps/workspace/components/forms/WorkspaceSecretForm.vue';

vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: vi.fn(() => ({
    currentContext: { value: { domain: '', displayName: '', isCanonical: true } },
    isContextActive: { value: false },
  })),
}));

vi.mock('@/shared/composables/useSecretConcealer', () => ({
  useSecretConcealer: vi.fn(() => ({
    form: { secret: '', passphrase: '', ttl: 604800, share_domain: '', recipient: '' },
    validation: { errors: new Map() },
    operations: { updateField: vi.fn(), reset: vi.fn() },
    isSubmitting: false,
    submit: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/useCharCounter', () => ({
  useCharCounter: vi.fn(() => ({
    isHovering: ref(false),
    formatNumber: (n: number) => String(n),
  })),
}));

vi.mock('@/shared/composables/useTextarea', () => ({
  useTextarea: vi.fn(() => ({
    content: ref(''),
    charCount: ref(0),
    textareaRef: ref(null),
    checkContentLength: vi.fn(),
    clearTextarea: vi.fn(),
  })),
}));

vi.mock('@/services/logging.service', () => ({
  loggingService: { debug: vi.fn(), error: vi.fn() },
}));

vi.mock('vue-router', () => ({
  useRouter: vi.fn(() => ({ push: vi.fn() })),
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

const RECIPIENT_SELECTOR = '#workspace-recipient';

const mountForm = (recipientCapability: boolean | undefined) => {
  const capabilities =
    recipientCapability === undefined ? {} : { recipient: recipientCapability };
  return mount(WorkspaceSecretForm, {
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            bootstrap: {
              ui: { capabilities },
              secret_options: { default_ttl: 604800 },
            },
          },
        }),
      ],
    },
  });
};

describe('WorkspaceSecretForm - recipient capability gating', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('hides the recipient field when ui.capabilities.recipient is false', () => {
    const wrapper = mountForm(false);
    expect(wrapper.find(RECIPIENT_SELECTOR).exists()).toBe(false);
  });

  it('shows the recipient field when ui.capabilities.recipient is true', () => {
    const wrapper = mountForm(true);
    expect(wrapper.find(RECIPIENT_SELECTOR).exists()).toBe(true);
  });

  it('shows the recipient field when the capability flag is unset (default enabled)', () => {
    const wrapper = mountForm(undefined);
    expect(wrapper.find(RECIPIENT_SELECTOR).exists()).toBe(true);
  });
});
