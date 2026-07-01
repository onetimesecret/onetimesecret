// src/tests/apps/secret/views/DisabledHomepage.spec.ts
//
// Regression guard: the dispatcher wrapper must not carry its own background
// color. It previously had a light-mode-only `bg-gray-50` surface, but that
// div sits inside `.homepage-container` (a plain non-flex block in
// Homepage.vue), so the flex-fill chain from <main> never reaches it — the
// surface only grows to the content's intrinsic height, not the full <main>
// height. In light mode that left a visible rectangle (the tinted content
// area) floating above a plain white gap before the footer; dark mode looked
// fine only by coincidence, since its `dark:bg-transparent` made the broken
// geometry invisible. See PR #3553 review.

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { createTestI18n } from '@tests/setup';
import DisabledHomepage from '@/apps/secret/views/DisabledHomepage.vue';

vi.mock('@/apps/secret/views/disabled/useDisabledConfig', () => ({
  useDisabledConfig: () => ({
    variant: { value: 'closed' },
    props: {
      isBranded: false,
      workspaceName: 'Acme',
      monogramInitial: 'A',
      primaryColor: '#3B82F6',
      logoUri: null,
      displayDomain: 'acme.example',
      showSignin: true,
      showWhatIsThis: false,
      whatIsThisHref: null,
      showPromo: false,
      promoHref: null,
      ssoOneClick: false,
      ssoProviderName: null,
      onSsoLogin: () => {},
    },
  }),
}));

describe('DisabledHomepage dispatcher', () => {
  it('does not apply a background color to its wrapper', () => {
    const wrapper = mount(DisabledHomepage, {
      global: { plugins: [createTestI18n()] },
    });

    const rootClasses = wrapper.classes();
    expect(rootClasses.some((c) => c.startsWith('bg-'))).toBe(false);
    expect(rootClasses.some((c) => c.startsWith('dark:bg-'))).toBe(false);
  });
});
