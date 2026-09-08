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

vi.mock('@/shared/composables/useAuth', () => ({
  useAuth: () => ({
    closeAccount: mockCloseAccount,
    isLoading: ref(false),
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
