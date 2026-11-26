// src/tests/apps/workspace/components/organizations/SharingPolicyForm.spec.ts

import SharingPolicyForm from '@/apps/workspace/components/organizations/SharingPolicyForm.vue';
import type { SharingPolicy } from '@/schemas/contracts/sharing-policy';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
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

describe('SharingPolicyForm when the installation already requires a passphrase', () => {
  const open: SharingPolicy = {
    recipient_email_mode: 'unrestricted',
    recipient_email_domains: [],
    passphrase_required: false,
    max_ttl: null,
  };
  const checkbox = '[data-testid="sharing-policy-passphrase"]';
  const note = '[data-testid="sharing-policy-passphrase-inherited"]';

  function mountOpen(instanceRequires: boolean) {
    const pinia = createTestingPinia({ createSpy: vi.fn });
    useBootstrapStore().$patch({
      secret_options: {
        default_ttl: 3600,
        ttl_options: [3600],
        passphrase: { required: instanceRequires, minimum_length: 4, maximum_length: 128 },
      },
    });
    const wrapper = mount(SharingPolicyForm, {
      props: { extid: 'on1abc', policy: open },
      global: { plugins: [createTestI18n(), pinia] },
    });
    const store = useOrganizationStore();
    vi.mocked(store.updateSharingPolicy).mockResolvedValue({ extid: 'on1abc' } as never);
    return { wrapper, store };
  }

  it('shows the box checked and disabled, with a note tied to it', () => {
    const { wrapper } = mountOpen(true);
    const box = wrapper.get<HTMLInputElement>(checkbox);

    expect(box.element.checked).toBe(true);
    expect(box.element.disabled).toBe(true);
    // The test i18n renders keys.
    expect(wrapper.get(note).text()).toBe(
      'web.organizations.sharing_policy.passphrase_required_by_instance'
    );
    expect(box.attributes('aria-describedby')).toBe(wrapper.get(note).attributes('id'));
  });

  it('does not write the inherited requirement into the organization policy', async () => {
    const { wrapper, store } = mountOpen(true);

    // Nothing of the organization's own changed, so there is nothing to save.
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(store.updateSharingPolicy).not.toHaveBeenCalled();

    // Saving another field keeps the stored passphrase_required: false.
    await wrapper.get('input[type="number"]').setValue(3600);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(store.updateSharingPolicy).toHaveBeenCalledWith('on1abc', { ...open, max_ttl: 3600 });
  });

  it('leaves the box editable, with no note, when the installation does not require one', async () => {
    const { wrapper, store } = mountOpen(false);
    const box = wrapper.get<HTMLInputElement>(checkbox);

    expect(box.element.checked).toBe(false);
    expect(box.element.disabled).toBe(false);
    expect(wrapper.find(note).exists()).toBe(false);

    await box.setValue(true);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(store.updateSharingPolicy).toHaveBeenCalledWith('on1abc', {
      ...open,
      passphrase_required: true,
    });
  });
});
