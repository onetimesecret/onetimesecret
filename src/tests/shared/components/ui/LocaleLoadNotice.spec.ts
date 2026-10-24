// src/tests/shared/components/ui/LocaleLoadNotice.spec.ts
//
// LocaleLoadNotice (src/shared/components/ui/LocaleLoadNotice.vue): the inline
// notice for a language whose messages did not load (F22). It names that
// language and the one shown instead, each in its own name and marked with
// its BCP 47 lang, says the visitor can carry on, and links to the feedback
// form. It renders while the language store holds a failure and goes away on
// dismissal.
//
// Mounted with the app's real i18n instance, so the copy asserted is the
// English the component ships (locales/content/en/10-layout.json).

import { flushPromises, mount, type VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span class="o-icon" />' },
}));

import i18n, { globalComposer } from '@/i18n';
import LocaleLoadNotice from '@/shared/components/ui/LocaleLoadNotice.vue';
import { useLanguageStore } from '@/shared/stores/languageStore';

describe('LocaleLoadNotice', () => {
  let wrapper: VueWrapper | undefined;

  beforeEach(() => {
    setActivePinia(createPinia());
    globalComposer.locale.value = 'en';
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
  });

  function render(failure: { requested: string; shown: string } | null) {
    useLanguageStore().localeLoadFailure = failure;
    wrapper = mount(LocaleLoadNotice, { global: { plugins: [i18n] } });
    return wrapper;
  }

  const notice = () => wrapper!.find('[data-testid="locale-load-notice"]');

  it('renders nothing while no failure is recorded', () => {
    render(null);

    expect(notice().exists()).toBe(false);
  });

  it('announces the failure as an alert, in English copy', () => {
    render({ requested: 'bg', shown: 'en' });

    expect(notice().attributes('role')).toBe('alert');
    expect(notice().text()).toContain('There was a problem loading Български');
    expect(notice().text()).toContain(
      'You can keep using the site in English. If this keeps happening, please ' +
        'let us know through the feedback form.'
    );
  });

  it('names both languages in their own names, each with its BCP 47 lang', () => {
    render({ requested: 'pt_BR', shown: 'nl' });

    const names = notice().findAll('span[lang]');
    expect(names.map((name) => [name.attributes('lang'), name.text()])).toEqual([
      ['pt-BR', 'Português (Brasil)'],
      ['nl', 'Nederlands'],
    ]);
  });

  it('falls back to the code for a language it has no name for', () => {
    render({ requested: 'sw', shown: 'en' });

    expect(notice().find('span[lang="sw"]').text()).toBe('sw');
  });

  it('links to the feedback form', () => {
    render({ requested: 'bg', shown: 'en' });

    const link = wrapper!.find('[data-testid="locale-load-notice-feedback"]');
    expect(link.element.tagName).toBe('A');
    expect(link.attributes('href')).toBe('/feedback');
    expect(link.text()).toBe('let us know through the feedback form');
  });

  it('is dismissed by its button, which clears the failure', async () => {
    render({ requested: 'bg', shown: 'en' });
    const dismiss = wrapper!.find('[data-testid="locale-load-notice-dismiss"]');
    expect(dismiss.attributes('aria-label')).toBe('Dismiss language notice');

    await dismiss.trigger('click');
    await flushPromises();

    expect(useLanguageStore().localeLoadFailure).toBeNull();
    expect(notice().exists()).toBe(false);
  });

  it('appears when a failure is recorded after it mounted', async () => {
    render(null);

    useLanguageStore().localeLoadFailure = { requested: 'bg', shown: 'en' };
    await flushPromises();

    expect(notice().exists()).toBe(true);
  });
});
