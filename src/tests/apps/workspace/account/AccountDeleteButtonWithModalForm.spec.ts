// src/tests/apps/workspace/account/AccountDeleteButtonWithModalForm.spec.ts

import AccountDeleteButtonWithModalForm from '@/apps/workspace/components/account/AccountDeleteButtonWithModalForm.vue';
import { mockCustomer } from '@tests/fixtures/bootstrap.fixture';
import { createTestI18n } from '@tests/setup';
import { mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
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

describe('AccountDeleteButtonWithModalForm', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsLoading.value = false;
    mockCloseAccount.mockResolvedValue(true);
  });

  it('closes the account through the Rodauth authentication flow', async () => {
    const wrapper = mount(AccountDeleteButtonWithModalForm, {
      props: { cust: mockCustomer },
      global: {
        plugins: [createTestI18n()],
        stubs: { RouterLink: true },
      },
    });

    await wrapper.get('[data-testid="account-delete-open-btn"]').trigger('click');
    await wrapper.get('[data-testid="account-delete-password-input"]').setValue('current-password');
    await wrapper.get('form').trigger('submit');
    await nextTick();

    expect(mockCloseAccount).toHaveBeenCalledOnce();
    expect(mockCloseAccount).toHaveBeenCalledWith('current-password');
  });

  it('does not submit an empty password', async () => {
    const wrapper = mount(AccountDeleteButtonWithModalForm, {
      props: { cust: mockCustomer },
      global: {
        plugins: [createTestI18n()],
        stubs: { RouterLink: true },
      },
    });

    await wrapper.get('[data-testid="account-delete-open-btn"]').trigger('click');
    await wrapper.get('form').trigger('submit');

    expect(mockCloseAccount).not.toHaveBeenCalled();
  });

  it('does not submit while a deletion is in progress', async () => {
    const wrapper = mount(AccountDeleteButtonWithModalForm, {
      props: { cust: mockCustomer },
      global: {
        plugins: [createTestI18n()],
        stubs: { RouterLink: true },
      },
    });

    await wrapper.get('[data-testid="account-delete-open-btn"]').trigger('click');
    await wrapper.get('[data-testid="account-delete-password-input"]').setValue('current-password');
    mockIsLoading.value = true;
    await wrapper.get('form').trigger('submit');

    expect(mockCloseAccount).not.toHaveBeenCalled();
  });

  const mountOpen = async () => {
    const wrapper = mount(AccountDeleteButtonWithModalForm, {
      props: { cust: mockCustomer },
      attachTo: document.body,
      global: {
        plugins: [createTestI18n()],
        stubs: { RouterLink: true },
      },
    });
    await wrapper.get('[data-testid="account-delete-open-btn"]').trigger('click');
    return wrapper;
  };
  const modal = (wrapper: ReturnType<typeof mount>) =>
    wrapper.find('[data-testid="account-delete-modal"]');

  it('closes on Escape', async () => {
    const wrapper = await mountOpen();
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await nextTick();
    expect(modal(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('closes on a backdrop click but not on a click inside the panel', async () => {
    const wrapper = await mountOpen();
    await wrapper.get('form').trigger('mousedown');
    await wrapper.get('form').trigger('click');
    expect(modal(wrapper).exists()).toBe(true);
    await modal(wrapper).trigger('mousedown');
    await modal(wrapper).trigger('click');
    expect(modal(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('stays open when a drag from the password field ends over the backdrop', async () => {
    const wrapper = await mountOpen();
    await wrapper.get('[data-testid="account-delete-password-input"]').setValue('current-password');
    await wrapper.get('[data-testid="account-delete-password-input"]').trigger('mousedown');
    await modal(wrapper).trigger('click');
    expect(modal(wrapper).exists()).toBe(true);
    expect(
      (wrapper.get('[data-testid="account-delete-password-input"]').element as HTMLInputElement).value
    ).toBe('current-password');
    wrapper.unmount();
  });

  it('stays open on Escape and backdrop click while a deletion is in progress', async () => {
    const wrapper = await mountOpen();
    mockIsLoading.value = true;
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await modal(wrapper).trigger('mousedown');
    await modal(wrapper).trigger('click');
    await nextTick();
    expect(modal(wrapper).exists()).toBe(true);
    wrapper.unmount();
  });

  it('clears authentication errors before opening and after closing the modal', async () => {
    const wrapper = mount(AccountDeleteButtonWithModalForm, {
      props: { cust: mockCustomer },
      global: {
        plugins: [createTestI18n()],
        stubs: { RouterLink: true },
      },
    });

    await wrapper.get('[data-testid="account-delete-open-btn"]').trigger('click');
    await wrapper.get('[data-testid="account-delete-cancel-btn"]').trigger('click');

    expect(mockClearErrors).toHaveBeenCalledTimes(2);
  });
});
