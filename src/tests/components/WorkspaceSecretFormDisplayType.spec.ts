// src/tests/components/WorkspaceSecretFormDisplayType.spec.ts
//
// The workspace form restores the remembered Markdown choice on load, but
// only while the platform has Markdown on (features.markdown). With it off,
// a remembered 'markdown' would be refused by the API and there is no chip
// to turn it off, so the form starts from plain text and the stored
// preference is left for when Markdown is back on.

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';
import WorkspaceSecretForm from '@/apps/workspace/components/forms/WorkspaceSecretForm.vue';
import { useLocalReceiptStore } from '@/shared/stores/localReceiptStore';

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

const mountForm = (markdown: boolean, preferredDisplayType: string | null) =>
  mount(WorkspaceSecretForm, {
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            bootstrap: {
              features: { markdown },
              secret_options: { default_ttl: 604800 },
            },
            localReceipt: { preferredDisplayType },
          },
        }),
      ],
    },
  });

const displayTypeUpdates = () =>
  mockUpdateField.mock.calls.filter(([field]) => field === 'display_type').map(([, v]) => v);

describe('WorkspaceSecretForm - remembered display type', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('restores a remembered markdown when the platform has Markdown on', () => {
    mountForm(true, 'markdown');
    expect(displayTypeUpdates()).toEqual(['markdown']);
  });

  it('starts from text, ignoring a remembered markdown, when the platform has Markdown off', () => {
    const wrapper = mountForm(false, 'markdown');
    expect(displayTypeUpdates()).toEqual(['text']);
    // The preference itself is kept for when Markdown is back on
    expect(useLocalReceiptStore().preferredDisplayType).toBe('markdown');
    expect(wrapper.find('[data-testid="secret-markdown-preview"]').exists()).toBe(false);
  });

  it('starts from text when nothing is remembered', () => {
    mountForm(true, null);
    expect(displayTypeUpdates()).toEqual(['text']);
  });
});
