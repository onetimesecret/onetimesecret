// src/tests/shared/components/ui/LocaleLoadNotice.spec.ts
//
// LocaleLoadNotice (src/shared/components/ui/LocaleLoadNotice.vue): the inline
// notice for a language whose messages did not load (F22). It names that
// language and the one shown instead, each in its own name and marked with
// its BCP 47 lang, says the visitor can carry on, and links to the feedback
// form. It renders while the language store records a failure and goes away on
// dismissal. Save failures offer retry/dismiss without implying the active
// language failed to load; load failures take priority.
//
// Mounted with the app's real i18n instance, so the copy asserted is the
// English the component ships (locales/content/en/10-layout.json).

import { flushPromises, mount, type VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span class="o-icon" />' },
}));

// Keep UI behavior independent of persistence; store actions are covered separately.
vi.mock('@/shared/stores/languageStore', async () => {
  const { defineStore } = await import('pinia');
  return {
    useLanguageStore: defineStore('language', {
      state: () => ({
        localeLoadFailure: null as { requested: string; shown: string } | null,
        localeSaveFailure: null as { locale: string; accountExtid: string | null } | null,
      }),
      actions: {
        retryLanguageSave() {
          return Promise.resolve();
        },
        dismissLocaleLoadFailure() {
          this.localeLoadFailure = null;
        },
        dismissLocaleSaveFailure() {
          this.localeSaveFailure = null;
        },
      },
    }),
  };
});

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
    vi.restoreAllMocks();
  });

  function render(failure: { requested: string; shown: string } | null) {
    useLanguageStore().localeLoadFailure = failure;
    wrapper = mount(LocaleLoadNotice, { global: { plugins: [i18n] } });
    return wrapper;
  }

  const notice = () => wrapper!.find('[data-testid="locale-load-notice"]');
  const saveNotice = () => wrapper!.find('[data-testid="locale-save-notice"]');
  const retryButton = () =>
    wrapper!.find<HTMLButtonElement>('[data-testid="locale-save-notice-retry"]');

  function renderSaveFailure(accountExtid: string | null = null) {
    useLanguageStore().localeSaveFailure = { locale: 'bg', accountExtid };
    return render(null);
  }

  it('renders nothing while no failure is recorded', () => {
    render(null);

    expect(notice().exists()).toBe(false);
    expect(saveNotice().exists()).toBe(false);
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

  it.each([null, 'account-123'])('announces a save failure for account %s', (accountExtid) => {
    renderSaveFailure(accountExtid);

    expect(saveNotice().attributes('role')).toBe('alert');
    expect(saveNotice().text()).toContain('Your language preference could not be saved');
    expect(saveNotice().text()).toContain(
      'Your current language remains active for this page. Retry to remember your language preference.'
    );
    expect(retryButton().text()).toBe('Retry');
    expect(retryButton().element.disabled).toBe(false);
    expect(notice().exists()).toBe(false);
    expect(saveNotice().find('a[href="/feedback"]').exists()).toBe(false);
  });

  it('appears when a save failure is recorded after mounting', async () => {
    render(null);

    useLanguageStore().localeSaveFailure = { locale: 'bg', accountExtid: null };
    await flushPromises();

    expect(saveNotice().exists()).toBe(true);
  });

  it('retries saving and disappears when the store clears the failure', async () => {
    renderSaveFailure();
    const store = useLanguageStore();
    const retry = vi.spyOn(store, 'retryLanguageSave').mockImplementation(async () => {
      store.localeSaveFailure = null;
    });

    await retryButton().trigger('click');
    await flushPromises();

    expect(retry).toHaveBeenCalledExactlyOnceWith();
    expect(saveNotice().exists()).toBe(false);
    expect(notice().exists()).toBe(false);
  });

  it('disables repeat retries while saving, then enables retry if the failure remains', async () => {
    renderSaveFailure();
    let finish!: () => void;
    const retry = vi.spyOn(useLanguageStore(), 'retryLanguageSave').mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          finish = resolve;
        })
    );

    // Dispatch twice before Vue updates the disabled attribute to exercise the local guard.
    retryButton().element.click();
    retryButton().element.click();
    await flushPromises();

    expect(retry).toHaveBeenCalledTimes(1);
    expect(retryButton().element.disabled).toBe(true);
    expect(retryButton().attributes('aria-busy')).toBe('true');
    expect(saveNotice().find('.animate-spin').exists()).toBe(true);
    await retryButton().trigger('click');
    expect(retry).toHaveBeenCalledTimes(1);

    finish();
    await flushPromises();

    expect(saveNotice().exists()).toBe(true);
    expect(retryButton().element.disabled).toBe(false);
    expect(retryButton().attributes('aria-busy')).toBe('false');
    expect(saveNotice().find('.animate-spin').exists()).toBe(false);

    await retryButton().trigger('click');
    expect(retry).toHaveBeenCalledTimes(2);
    finish();
    await flushPromises();
  });

  it('dismisses a save failure through the store action', async () => {
    renderSaveFailure();
    const store = useLanguageStore();
    const dismissAction = vi.spyOn(store, 'dismissLocaleSaveFailure');
    const dismiss = wrapper!.find('[data-testid="locale-save-notice-dismiss"]');
    expect(dismiss.attributes('aria-label')).toBe('Dismiss language preference notice');

    await dismiss.trigger('click');
    await flushPromises();

    expect(dismissAction).toHaveBeenCalledExactlyOnceWith();
    expect(store.localeSaveFailure).toBeNull();
    expect(saveNotice().exists()).toBe(false);
  });

  it('prioritizes a load failure, leaving the save failure for after load dismissal', async () => {
    const store = useLanguageStore();
    store.localeSaveFailure = { locale: 'bg', accountExtid: null };
    const retry = vi.spyOn(store, 'retryLanguageSave');
    render({ requested: 'bg', shown: 'en' });

    expect(notice().exists()).toBe(true);
    expect(saveNotice().exists()).toBe(false);
    expect(retryButton().exists()).toBe(false);
    expect(wrapper!.find('[data-testid="locale-load-notice-feedback"]').exists()).toBe(true);

    await wrapper!.find('[data-testid="locale-load-notice-dismiss"]').trigger('click');
    await flushPromises();

    expect(store.localeLoadFailure).toBeNull();
    expect(store.localeSaveFailure).toEqual({ locale: 'bg', accountExtid: null });
    expect(notice().exists()).toBe(false);
    expect(saveNotice().exists()).toBe(true);
    expect(retry).not.toHaveBeenCalled();
  });
});
