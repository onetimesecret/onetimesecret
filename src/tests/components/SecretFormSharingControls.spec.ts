import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { flushPromises, mount, type VueWrapper } from '@vue/test-utils';
import { setActivePinia } from 'pinia';
import { nextTick } from 'vue';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
import type { SharingPolicy } from '@/schemas/contracts/sharing-policy';
import { __resetDomainContextForTesting, useDomainContext } from '@/shared/composables/useDomainContext';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useSecretStore } from '@/shared/stores/secretStore';
import type { Organization } from '@/types/organization';

const fetchAllPermissions = vi.fn();
vi.mock('@/shared/composables/useResourcePermissions', () => ({
  useResourcePermissions: () => ({ fetchAllPermissions }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));

const unrestricted: SharingPolicy = {
  recipient_email_mode: 'unrestricted', recipient_email_domains: [],
  passphrase_required: false, max_ttl: null,
};

function organization(id: string, policy = unrestricted): Organization {
  return {
    objid: id, extid: id, display_name: id, description: null, contact_email: null,
    is_default: false, is_current_user_default: false, active_subscription: false,
    planid: 'free_v1', created: new Date(), updated: new Date(),
    sharing_policy: policy, limits: { secret_lifetime: -1 },
  };
}

function snapshot(id: string, domains: Record<string, boolean>) {
  return { organizations: [{ extid: id, domains: Object.entries(domains).map(([name, required]) => ({
    extid: name, display_domain: name, served: true, passphrase_required: required,
  })) }] };
}

const passphrase = '[data-testid="secret-passphrase-input"]';
const recipient = '[data-testid="secret-recipient-input"]';
const ttl = '[data-testid="secret-ttl-select"]';
let wrapper: VueWrapper;

function setup(org: Organization) {
  const pinia = createTestingPinia({ createSpy: vi.fn });
  setActivePinia(pinia);
  const bootstrap = useBootstrapStore();
  bootstrap.$patch({
    authenticated: true, site_host: 'canonical.example', domain_strategy: 'canonical',
    domains_enabled: true, secret_options: { default_ttl: 3600, ttl_options: [60, 3600] },
  });
  const organizations = useOrganizationStore();
  organizations.currentOrganization = org;
  const render = () => {
    wrapper = mount(SecretForm, {
      props: { enabled: true, withRecipient: true },
      global: { plugins: [pinia, createTestI18n()], provide: { api: {} } },
    });
  };
  return { bootstrap, organizations, render };
}

describe('sharing controls in the creation form', () => {
  beforeEach(() => {
    fetchAllPermissions.mockReset().mockResolvedValue({ organizations: [] });
    sessionStorage.clear();
  });

  afterEach(() => {
    wrapper.unmount();
    __resetDomainContextForTesting();
  });

  it.each([true, false])('labels the minimum length hint as optional only when passphrase required=%s is false', async required => {
    const { bootstrap, render } = setup(organization('org', { ...unrestricted, passphrase_required: required }));
    bootstrap.$patch({ secret_options: {
      default_ttl: 3600, ttl_options: [60, 3600], passphrase: { minimum_length: 4 },
    } });
    render();
    await flushPromises();
    const hint = wrapper.get(passphrase).element.closest('.relative')!.parentElement!.textContent ?? '';
    // The test i18n renders keys. The plain key's English text ends "(Optional)".
    expect(hint.includes('web.secrets.passphraseMinimumLengthRequired')).toBe(required);
    expect(/passphraseMinimumLength(?!Required)/.test(hint)).toBe(!required);
  });

  it('keeps the error banner below page menus and lifts the card while its menu is open', async () => {
    const { render } = setup(organization('org'));
    render();
    await flushPromises();
    // jsdom has no layout, so this pins the classes the stacking order relies on.
    const banner = wrapper.get('[data-testid="secret-form-alerts"]');
    expect(banner.classes()).toContain('z-[5]');
    expect(banner.classes()).not.toContain('z-50');
    const toggle = wrapper.get('[data-testid="split-button-dropdown-toggle"]');
    expect(toggle.attributes('aria-haspopup')).toBe('true');
    const card = toggle.element.closest('.backdrop-blur-sm')!;
    expect(card.classList).toContain('relative');
    expect(card.classList).toContain('has-[[aria-haspopup][aria-expanded=true]]:z-10');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');
  });

  it.each([true, false])('replaces an edited host policy and keeps domain passphrase=%s', async required => {
    const { bootstrap, organizations, render } = setup(organization('host', {
      ...unrestricted, max_ttl: 90, passphrase_required: true, recipient_email_mode: 'disabled',
    }));
    bootstrap.$patch({
      domain_strategy: 'custom', display_domain: 'host.example', link_domains: ['links.example'],
      secret_options: { host_sharing_policy: {
        max_ttl: 90, passphrase_required: true, recipient_email_mode: 'disabled',
        organization_extid: 'host', domain_passphrase_required: required,
      } },
    });
    render();
    await flushPromises();
    expect(wrapper.get(passphrase).attributes('required')).toBeDefined();
    expect(wrapper.find(recipient).exists()).toBe(false);
    expect(wrapper.get<HTMLSelectElement>(ttl).element.value).toBe('90');

    organizations.currentOrganization = organization('host');
    await nextTick();
    expect(wrapper.get(passphrase).attributes('required') !== undefined).toBe(required);
    expect(wrapper.find(recipient).exists()).toBe(true);
    expect(wrapper.get<HTMLInputElement>(recipient).element.multiple).toBe(false);
    expect(wrapper.get<HTMLSelectElement>(ttl).element.value).toBe('90');
    expect(wrapper.find('option[value="3600"]').exists()).toBe(true);
    await wrapper.get('textarea').setValue('draft secret');
    if (required) await wrapper.get(passphrase).setValue('secret passphrase');
    await wrapper.get('form').trigger('submit');
    expect(useSecretStore().conceal).toHaveBeenCalledWith(expect.objectContaining({ ttl: 90 }));
  });

  it('clears the draft recipient when the host and workspace have no common domain', async () => {
    const { bootstrap, organizations, render } = setup(organization('first'));
    bootstrap.$patch({
      domain_strategy: 'custom', display_domain: 'branded.example', link_domains: ['links.example'],
      secret_options: { host_sharing_policy: {
        max_ttl: 3600, passphrase_required: false, recipient_email_mode: 'restricted',
        recipient_email_domains: ['first.example'],
      } },
    });
    render();
    await wrapper.get(recipient).setValue('person@first.example');
    organizations.currentOrganization = organization('second', {
      ...unrestricted, recipient_email_mode: 'restricted', recipient_email_domains: ['second.example'],
    });
    await nextTick();
    expect(wrapper.find(recipient).exists()).toBe(false);
    organizations.currentOrganization = organization('first');
    await nextTick();
    expect(wrapper.get<HTMLInputElement>(recipient).element.value).toBe('');
  });

  it('retires a selected domain before submitting during delayed and failed organization switches', async () => {
    const { organizations, render } = setup(organization('first'));
    fetchAllPermissions.mockResolvedValueOnce(snapshot('first', {
      'locked.example': true, 'open.example': false,
    }));
    render();
    await flushPromises();
    const context = useDomainContext();
    expect(wrapper.get(passphrase).attributes('required')).toBeDefined();
    await context.setContext('open.example', true);
    expect(wrapper.get(passphrase).attributes('required')).toBeUndefined();
    await context.setContext('locked.example', true);
    fetchAllPermissions.mockResolvedValueOnce(null);
    expect(await context.refreshDomains()).toBe(false);
    expect(wrapper.get(passphrase).attributes('required')).toBeDefined();

    await wrapper.get('textarea').setValue('draft secret');
    let finishOldRequest!: (value: ReturnType<typeof snapshot>) => void;
    fetchAllPermissions.mockImplementationOnce(() => new Promise(resolve => { finishOldRequest = resolve; }));
    organizations.currentOrganization = organization('second');
    expect(context.currentContext.value.domain).toBe('canonical.example');
    // Submit in the same turn as the switch, before the permission reply.
    await wrapper.get('form').trigger('submit');
    expect(useSecretStore().conceal).toHaveBeenCalledWith(expect.objectContaining({ share_domain: 'canonical.example' }));

    fetchAllPermissions.mockResolvedValueOnce(null);
    organizations.currentOrganization = organization('third');
    await flushPromises();
    finishOldRequest(snapshot('second', { 'late.example': true }));
    await flushPromises();
    expect(context.availableDomains.value).toEqual(['canonical.example']);
    expect(wrapper.get(passphrase).attributes('required')).toBeUndefined();
    await wrapper.get('form').trigger('submit');
    expect(vi.mocked(useSecretStore().conceal).mock.lastCall?.[0].share_domain).toBe('canonical.example');
  });
});
