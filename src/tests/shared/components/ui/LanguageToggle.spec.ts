// src/tests/shared/components/ui/LanguageToggle.spec.ts
//
// LanguageToggle while a switch is loading (F20). The visitor's latest choice
// is the pending locale, if any, else the active one: it decides whether a
// pick is a new choice, whether "reset to default" is offered, and the name
// in the menu header. While nl loads the page is still English, and picking
// English again must supersede the pending switch, not be ignored as "already
// active".
//
// useLanguage is replaced with plain refs so each state can be set directly;
// the store's side of a superseded switch is in the languageStore specs.

import { flushPromises, mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

const language = vi.hoisted(() => ({
  currentLocale: null as unknown as { value: string },
  pendingLocale: null as unknown as { value: string | null },
  updateLanguage: null as unknown as ReturnType<typeof vi.fn>,
}));

vi.mock('@/shared/composables/useLanguage', () => ({
  useLanguage: () => ({
    currentLocale: language.currentLocale,
    pendingLocale: language.pendingLocale,
    supportedLocalesWithNames: ref({ en: 'English', nl: 'Nederlands', bg: 'Български' }),
    updateLanguage: language.updateLanguage,
    initializeLanguage: vi.fn(),
  }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span class="o-icon" />' },
}));

import LanguageToggle from '@/shared/components/ui/LanguageToggle.vue';
import { createTestI18n } from '@tests/setup';

describe('LanguageToggle while a switch loads (F20)', () => {
  let wrapper: VueWrapper | undefined;

  beforeEach(() => {
    language.currentLocale = ref('en');
    language.pendingLocale = ref(null);
    language.updateLanguage = vi.fn(async () => undefined);
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
  });

  async function openMenu() {
    wrapper = mount(LanguageToggle, { global: { plugins: [createTestI18n()] } });
    await wrapper.find('[data-testid="language-toggle"]').trigger('click');
    return wrapper;
  }

  const item = (code: string) => wrapper!.find(`[role="menuitem"][lang="${code}"]`);
  // With pass-through i18n the reset button's title is its key.
  const resetButton = () => wrapper!.find('button[title="web.layout.reset_to_default_language"]');
  const menuHeader = () => wrapper!.find('[role="presentation"]');

  it('ignores a pick of the active locale when nothing is loading', async () => {
    await openMenu();

    await item('en').trigger('click');

    expect(language.updateLanguage).not.toHaveBeenCalled();
  });

  it('treats a pick of the active locale as a new choice while another one loads', async () => {
    language.pendingLocale.value = 'nl';
    await openMenu();

    await item('en').trigger('click');

    expect(language.updateLanguage).toHaveBeenCalledWith('en');
  });

  it('ignores a second pick of the locale that is loading', async () => {
    language.pendingLocale.value = 'nl';
    await openMenu();

    await item('nl').trigger('click');

    expect(language.updateLanguage).not.toHaveBeenCalled();
  });

  it('names the loading locale in the header and offers to reset to the default', async () => {
    language.pendingLocale.value = 'nl';
    await openMenu();

    expect(menuHeader().text()).toContain('Nederlands');
    expect(resetButton().exists()).toBe(true);

    await resetButton().trigger('click');
    expect(language.updateLanguage).toHaveBeenCalledWith('en');
  });

  it('offers no reset with the default active and nothing loading', async () => {
    await openMenu();

    expect(menuHeader().text()).toContain('English');
    expect(resetButton().exists()).toBe(false);
  });

  // updateLanguage resolves whether the switch took effect or not.
  it('announces a switch only once its locale is active', async () => {
    await openMenu();

    await item('bg').trigger('click');
    await flushPromises();
    expect(wrapper!.emitted('localeChanged')).toBeUndefined();

    language.updateLanguage.mockImplementation(async () => {
      language.currentLocale.value = 'nl';
    });
    await wrapper!.find('[data-testid="language-toggle"]').trigger('click');
    await item('nl').trigger('click');
    await flushPromises();
    expect(wrapper!.emitted('localeChanged')).toEqual([['nl']]);
  });
});
