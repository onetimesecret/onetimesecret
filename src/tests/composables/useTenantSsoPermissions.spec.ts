import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, ref } from 'vue';
import { describe, expect, it, vi } from 'vitest';
import { useTenantSsoPermissions } from '@/shared/composables/useResourcePermissions';

function response(org: string, domain: string, allowed?: boolean) {
  return { data: {
    resource_type: 'domain', resource_id: domain,
    organization: { extid: org, display_name: org },
    membership: { role: 'owner', status: 'active', provisioning_source: null,
      invited_at: null, joined_at: null, entitlements: [] },
    permissions: { can_view: false, can_edit: false, can_delete: false,
      can_manage_settings: true, can_manage_sso: allowed },
    domain: { display_domain: domain, verified: true },
  } };
}

describe('useTenantSsoPermissions', () => {
  function setup(get: ReturnType<typeof vi.fn>) {
    const org = ref('org-a');
    const domain = ref('a.example');
    const wrapper = mount(defineComponent({
      setup: () => useTenantSsoPermissions(() => org.value, () => domain.value),
      template: '<div/>',
    }), { global: { provide: { api: { get } } } });
    return { wrapper, domain, org };
  }

  it('clears displayed permission and metadata before a new lookup and ignores late results', async () => {
    let finish!: (value: ReturnType<typeof response>) => void;
    const get = vi.fn().mockResolvedValueOnce(response('org-a', 'a.example', true))
      .mockReturnValueOnce(new Promise(resolve => { finish = resolve; }))
      .mockResolvedValueOnce(response('org-a', 'c.example', false));
    const { wrapper, domain } = setup(get);
    await flushPromises();
    expect(wrapper.vm.canManageSso).toBe(true);
    expect(wrapper.vm.domain?.display_domain).toBe('a.example');
    domain.value = 'b.example';
    expect(wrapper.vm.canManageSso).toBeUndefined();
    expect(wrapper.vm.domain).toBeUndefined();
    domain.value = 'c.example';
    await flushPromises();
    finish(response('org-a', 'b.example', true));
    await flushPromises();
    expect(wrapper.vm.canManageSso).toBe(false);
    expect(wrapper.vm.domain).toBeUndefined();
    wrapper.unmount();
  });

  it.each([
    ['another organization', response('org-b', 'a.example', true)],
    ['another domain', response('org-a', 'b.example', true)],
    ['an older server', response('org-a', 'a.example')],
  ])('leaves permission unconfirmed for %s', async (_case, result) => {
    const { wrapper } = setup(vi.fn().mockResolvedValue(result));
    await flushPromises();
    expect(wrapper.vm.canManageSso).toBeUndefined();
    expect(wrapper.vm.domain).toBeUndefined();
    expect(wrapper.vm.isLoading).toBe(false);
    wrapper.unmount();
  });
});
