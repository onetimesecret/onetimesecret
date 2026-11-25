// src/tests/apps/workspace/components/organizations/SharingPolicyForm.spec.ts

import SharingPolicyForm from '@/apps/workspace/components/organizations/SharingPolicyForm.vue';
import type { SharingPolicy } from '@/schemas/contracts/sharing-policy';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount } from '@vue/test-utils';
import { createTestI18n } from '@tests/setup';
import { describe, expect, it, vi } from 'vitest';

// The server substitutes this policy when the stored one cannot be read.
const strictest: SharingPolicy = {
  recipient_email_mode: 'disabled',
  recipient_email_domains: [],
  passphrase_required: true,
  max_ttl: 60,
};

function mountForm(invalid?: boolean) {
  const pinia = createTestingPinia({ createSpy: vi.fn });
  const wrapper = mount(SharingPolicyForm, {
    props: { extid: 'on1abc', policy: strictest, ...(invalid === undefined ? {} : { invalid }) },
    global: { plugins: [createTestI18n(), pinia] },
  });
  const store = useOrganizationStore();
  vi.mocked(store.updateSharingPolicy).mockResolvedValue({ extid: 'on1abc' } as never);
  return { wrapper, store };
}

describe('SharingPolicyForm with an unreadable stored policy', () => {
  it('shows the invalid-policy notice and lets the owner save the shown policy', async () => {
    const { wrapper, store } = mountForm(true);
    expect(wrapper.find('[data-testid="sharing-policy-invalid"]').exists()).toBe(true);

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(store.updateSharingPolicy).toHaveBeenCalledWith('on1abc', strictest);
  });

  it('hides the notice and skips an unchanged save for a readable policy', async () => {
    const { wrapper, store } = mountForm();
    expect(wrapper.find('[data-testid="sharing-policy-invalid"]').exists()).toBe(false);

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(store.updateSharingPolicy).not.toHaveBeenCalled();
  });
});
