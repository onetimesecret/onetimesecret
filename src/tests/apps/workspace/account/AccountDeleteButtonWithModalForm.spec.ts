// src/tests/apps/workspace/account/AccountDeleteButtonWithModalForm.spec.ts

import AccountDeleteButtonWithModalForm from '@/apps/workspace/components/account/AccountDeleteButtonWithModalForm.vue';
import { mockCustomer } from '@tests/fixtures/bootstrap.fixture';
import { createTestI18n } from '@tests/setup';
import { DOMWrapper, enableAutoUnmount, mount } from '@vue/test-utils';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, ref } from 'vue';

const { mockCloseAccount, mockClearErrors } = vi.hoisted(() => ({
  mockCloseAccount: vi.fn(),
  mockClearErrors: vi.fn(),
}));
const mockIsLoading = ref(false);

vi.mock('@/shared/composables/useAuth', () => ({
  useAuth: () => ({
    closeAccount: mockCloseAccount,
    isLoading: mockIsLoading,
    error: ref(null),
    clearErrors: mockClearErrors,
  }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span />',
  },
}));

enableAutoUnmount(afterEach);

describe('AccountDeleteButtonWithModalForm', () => {
  // Headless UI observes whether the open dialog has disappeared from layout.
  beforeAll(() => vi.stubGlobal('ResizeObserver', class {
    observe() {}
    disconnect() {}
  }));
  afterAll(() => vi.unstubAllGlobals());

  beforeEach(() => {
    vi.clearAllMocks();
    mockIsLoading.value = false;
    mockCloseAccount.mockResolvedValue(true);
  });

  const mountOpen = async () => {
    const wrapper = mount(AccountDeleteButtonWithModalForm, {
      attachTo: document.body,
      props: { cust: mockCustomer },
      global: {
        plugins: [createTestI18n()],
        stubs: { RouterLink: true },
      },
    });
    const opener = wrapper.get<HTMLButtonElement>('[data-testid="account-delete-open-btn"]');
    opener.element.focus();
    await opener.trigger('click');
    return new DOMWrapper(document.body);
  };

  const modal = (page: DOMWrapper<HTMLElement>) => page.find('[data-testid="account-delete-modal"]');

  it('closes the account through the Rodauth authentication flow', async () => {
    const page = await mountOpen();
    await page.get('[data-testid="account-delete-password-input"]').setValue('current-password');
    await page.get('form').trigger('submit');
    expect(mockCloseAccount).toHaveBeenCalledOnce();
    expect(mockCloseAccount).toHaveBeenCalledWith('current-password');
  });

  it('does not submit an empty password', async () => {
    const page = await mountOpen();
    await page.get('form').trigger('submit');
    expect(mockCloseAccount).not.toHaveBeenCalled();
  });

  it('does not submit while a deletion is in progress', async () => {
    const page = await mountOpen();
    await page.get('[data-testid="account-delete-password-input"]').setValue('current-password');
    mockIsLoading.value = true;
    await page.get('form').trigger('submit');
    expect(mockCloseAccount).not.toHaveBeenCalled();
  });

  it('names the dialog and moves focus inside when it opens', async () => {
    const page = await mountOpen();
    const dialog = modal(page);
    expect(dialog.attributes('aria-labelledby')).toBe(dialog.get('h3').attributes('id'));
    expect(dialog.element.contains(document.activeElement)).toBe(true);
  });

  it('closes on Escape', async () => {
    const page = await mountOpen();
    await page.get('input[type="password"]').trigger('keydown', { key: 'Escape' });
    await nextTick();
    expect(modal(page).exists()).toBe(false);
    expect(document.activeElement).toBe(page.get('[data-testid="account-delete-open-btn"]').element);
  });

  it('closes on a backdrop click but not on a click inside the panel', async () => {
    const page = await mountOpen();
    await page.get('form').trigger('mousedown');
    await page.get('form').trigger('click');
    expect(modal(page).exists()).toBe(true);
    await modal(page).trigger('mousedown');
    await modal(page).trigger('click');
    expect(modal(page).exists()).toBe(false);
  });

  it('stays open when a drag from the password field ends over the backdrop', async () => {
    const page = await mountOpen();
    await page.get('[data-testid="account-delete-password-input"]').setValue('current-password');
    await page.get('[data-testid="account-delete-password-input"]').trigger('mousedown');
    await modal(page).trigger('click');
    expect(modal(page).exists()).toBe(true);
    expect(
      (page.get('[data-testid="account-delete-password-input"]').element as HTMLInputElement).value
    ).toBe('current-password');
  });

  it('stays open on Escape and backdrop click while a deletion is in progress', async () => {
    const page = await mountOpen();
    mockIsLoading.value = true;
    await page.get('input[type="password"]').trigger('keydown', { key: 'Escape' });
    await modal(page).trigger('mousedown');
    await modal(page).trigger('click');
    await nextTick();
    expect(modal(page).exists()).toBe(true);
    expect(page.get<HTMLButtonElement>('[data-testid="account-delete-cancel-btn"]').element.disabled).toBe(true);
  });

  it('clears authentication errors before opening and after closing the modal', async () => {
    const page = await mountOpen();
    await page.get('[data-testid="account-delete-cancel-btn"]').trigger('click');
    expect(mockClearErrors).toHaveBeenCalledTimes(2);
  });
});
