// src/tests/apps/workspace/components/domains/DomainHomepageNetworkAccess.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import DomainHomepageNetworkAccess from '@/apps/workspace/components/domains/DomainHomepageNetworkAccess.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name'],
  },
}));

function mountEditor(props: Record<string, unknown> = {}) {
  return mount(DomainHomepageNetworkAccess, {
    props: {
      allowedCidrs: [],
      deniedCidrs: [],
      ...props,
    },
    slots: { upgrade: '<a data-testid="upgrade-link">plans</a>' },
  });
}

type Editor = ReturnType<typeof mountEditor>;

async function addAllowed(wrapper: Editor, entry: string) {
  const input = wrapper.find('#homepage-network-allowed-input');
  await input.setValue(entry);
  await input.trigger('keydown', { key: 'Enter' });
}

function allowedChips(wrapper: Editor): string[] {
  return wrapper
    .find('[data-testid="homepage-network-allowed"]')
    .findAll('[role="listitem"]')
    .map((chip) => chip.text());
}

describe('DomainHomepageNetworkAccess', () => {
  it('renders the stored lists as chips', () => {
    const wrapper = mountEditor({ allowedCidrs: ['10.0.0.0/8', '2001:db8::/32'] });
    expect(allowedChips(wrapper)).toEqual(['10.0.0.0/8', '2001:db8::/32']);
    expect(wrapper.find('[data-testid="homepage-network-save"]').exists()).toBe(false);
  });

  it('stages an added entry and emits the dirty state', async () => {
    const wrapper = mountEditor();
    await addAllowed(wrapper, '192.0.2.0/24');

    expect(allowedChips(wrapper)).toEqual(['192.0.2.0/24']);
    expect(wrapper.find('[data-testid="homepage-network-save"]').exists()).toBe(true);
    expect(wrapper.emitted('update:dirty')).toEqual([[true]]);
  });

  it('emits both lists on save', async () => {
    const wrapper = mountEditor({ deniedCidrs: ['198.51.100.7/32'] });
    await addAllowed(wrapper, '192.0.2.0/24');
    await wrapper.find('[data-testid="homepage-network-save"]').trigger('click');

    expect(wrapper.emitted('save')).toEqual([
      [{ allowed_cidrs: ['192.0.2.0/24'], denied_cidrs: ['198.51.100.7/32'] }],
    ]);
  });

  it('keeps staged edits when an unrelated refresh replaces the stored lists', async () => {
    // Regression: the experience selector's save refetches the domain, which
    // hands the editor fresh (equal) arrays. That must not wipe staged edits.
    const wrapper = mountEditor({ allowedCidrs: ['10.0.0.0/8'] });
    await addAllowed(wrapper, '192.0.2.0/24');

    await wrapper.setProps({ allowedCidrs: ['10.0.0.0/8'], deniedCidrs: [] });

    expect(allowedChips(wrapper)).toEqual(['10.0.0.0/8', '192.0.2.0/24']);
    expect(wrapper.find('[data-testid="homepage-network-save"]').exists()).toBe(true);
  });

  it('re-seeds an unedited list from a refresh', async () => {
    const wrapper = mountEditor({ allowedCidrs: ['10.0.0.0/8'] });

    await wrapper.setProps({ allowedCidrs: ['10.0.0.0/8', '172.16.0.0/12'] });

    expect(allowedChips(wrapper)).toEqual(['10.0.0.0/8', '172.16.0.0/12']);
    expect(wrapper.emitted('update:dirty')).toBeUndefined();
  });

  it('re-seeds from the normalized record when its own save lands', async () => {
    const wrapper = mountEditor();
    await addAllowed(wrapper, '192.0.2.1');
    await wrapper.find('[data-testid="homepage-network-save"]').trigger('click');

    // The parent holds `saving` until its post-save refetch is in.
    await wrapper.setProps({ saving: true });
    await wrapper.setProps({ allowedCidrs: ['192.0.2.1/32'] });
    await wrapper.setProps({ saving: false });

    expect(allowedChips(wrapper)).toEqual(['192.0.2.1/32']);
    expect(wrapper.find('[data-testid="homepage-network-save"]').exists()).toBe(false);
    expect(wrapper.emitted('update:dirty')).toEqual([[true], [false]]);
  });

  it('discard restores the stored lists', async () => {
    const wrapper = mountEditor({ allowedCidrs: ['10.0.0.0/8'] });
    await addAllowed(wrapper, '192.0.2.0/24');
    await wrapper.find('[data-testid="homepage-network-discard"]').trigger('click');

    expect(allowedChips(wrapper)).toEqual(['10.0.0.0/8']);
    expect(wrapper.emitted('update:dirty')).toEqual([[true], [false]]);
  });

  it('offers only the upgrade link when locked without rules', () => {
    const wrapper = mountEditor({ locked: true });

    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.find('[data-testid="homepage-network-allowed"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="homepage-network-locked"]').text()).toContain(
      'web.domains.homepage.network_locked_note'
    );
    expect(wrapper.find('[data-testid="upgrade-link"]').exists()).toBe(true);
  });

  it('shows enforced rules read-only when locked', () => {
    // A downgrade freezes the lists rather than dropping them: they stay
    // enforced, so the operator must still see them, but cannot edit them.
    const wrapper = mountEditor({ locked: true, allowedCidrs: ['10.0.0.0/8'] });

    expect(allowedChips(wrapper)).toEqual(['10.0.0.0/8']);
    expect(wrapper.find('[data-testid="homepage-network-allowed"] button').exists()).toBe(false);
    expect(wrapper.find('[data-testid="homepage-network-denied"]').exists()).toBe(false);
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.find('[data-testid="homepage-network-locked"]').text()).toContain(
      'web.domains.homepage.network_locked_enforced_note'
    );
  });

  it('refuses an entry that is not address-shaped', async () => {
    const wrapper = mountEditor();
    await addAllowed(wrapper, 'example.com');

    expect(allowedChips(wrapper)).toEqual([]);
    expect(wrapper.find('#homepage-network-allowed-error').text()).toBe(
      'web.domains.homepage.network_invalid_entry'
    );
  });
});
