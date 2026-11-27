// src/tests/components/WorkspaceSecretFormPreferredTtl.spec.ts
//
// The workspace form restores the last-used lifetime on load. A lifetime
// outside the presets (a non-preset ceiling picked earlier) is kept exactly
// while it is within the bounds the form offers, instead of resetting to the
// default on every reload.

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';
import WorkspaceSecretForm from '@/apps/workspace/components/forms/WorkspaceSecretForm.vue';

const mockUpdateField = vi.fn();

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
    operations: { updateField: mockUpdateField, reset: vi.fn() },
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

const mountForm = (preferredTtl: number | null) =>
  mount(WorkspaceSecretForm, {
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            bootstrap: {
              secret_options: { default_ttl: 604800, ttl_options: [3600, 86400, 604800] },
            },
            localReceipt: { preferredTtl },
          },
        }),
      ],
    },
  });

const ttlUpdates = () =>
  mockUpdateField.mock.calls.filter(([field]) => field === 'ttl').map(([, v]) => v);

describe('WorkspaceSecretForm - remembered lifetime', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('restores a remembered preset', () => {
    mountForm(86400);
    expect(ttlUpdates()).toEqual([86400]);
  });

  it('restores a remembered lifetime outside the presets, exactly', () => {
    mountForm(3602);
    expect(ttlUpdates()).toEqual([3602]);
  });

  it('falls back to the default for a lifetime under a minute', () => {
    mountForm(30);
    expect(ttlUpdates()).toEqual([604800]);
  });

  it('falls back to the default for a lifetime over the 365-day bound', () => {
    mountForm(3600 * 24 * 366);
    expect(ttlUpdates()).toEqual([604800]);
  });

  it('uses the default when nothing is remembered', () => {
    mountForm(null);
    expect(ttlUpdates()).toEqual([604800]);
  });
});
