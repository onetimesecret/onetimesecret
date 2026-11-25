// src/tests/shared/components/ui/SettingsCard.spec.ts

import SettingsCard from '@/shared/components/ui/SettingsCard.vue';
import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name'],
  },
}));

describe('SettingsCard', () => {
  it('renders the title as an h2 and the body, with no icon, description or footer', () => {
    const wrapper = mount(SettingsCard, {
      props: { title: 'Sharing controls' },
      slots: { default: '<p data-testid="body">Body</p>' },
    });

    expect(wrapper.element.tagName).toBe('SECTION');
    expect(wrapper.get('h2').text()).toBe('Sharing controls');
    expect(wrapper.find('[data-testid="body"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="settings-card-icon"]').exists()).toBe(false);
    expect(wrapper.findAll('p')).toHaveLength(1);
    expect(wrapper.findAll('section > div')).toHaveLength(2);
  });

  it('renders the icon tile, description, heading level, actions and footer it is given', () => {
    const wrapper = mount(SettingsCard, {
      props: {
        title: 'Incoming Secrets',
        description: 'Who can receive secrets',
        icon: 'inbox-arrow-down',
        headingLevel: 3,
      },
      slots: {
        actions: '<button data-testid="action">Add</button>',
        footer: '<button data-testid="save">Save</button>',
      },
    });

    expect(wrapper.find('h2').exists()).toBe(false);
    expect(wrapper.get('h3').text()).toBe('Incoming Secrets');
    expect(wrapper.text()).toContain('Who can receive secrets');
    expect(
      wrapper.get('[data-testid="settings-card-icon"] .o-icon').attributes('data-icon-name')
    ).toBe('inbox-arrow-down');
    expect(wrapper.find('[data-testid="action"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="save"]').exists()).toBe(true);
    expect(wrapper.findAll('section > div')).toHaveLength(3);
  });

  it('passes attributes to the root so a tabbed page can make it the tabpanel', () => {
    const wrapper = mount(SettingsCard, {
      props: { title: 'Sharing controls' },
      attrs: { id: 'org-panel-sharing', role: 'tabpanel', 'aria-labelledby': 'org-tab-sharing' },
    });

    expect(wrapper.attributes()).toMatchObject({
      id: 'org-panel-sharing',
      role: 'tabpanel',
      'aria-labelledby': 'org-tab-sharing',
    });
  });

  it('takes the solid shell by default and the glass shell on request', () => {
    const solid = mount(SettingsCard, { props: { title: 'A' } });
    const glass = mount(SettingsCard, { props: { title: 'A', variant: 'glass' } });

    expect(solid.classes()).toContain('bg-white');
    expect(solid.classes()).not.toContain('backdrop-blur-sm');
    expect(glass.classes()).toContain('backdrop-blur-sm');
  });
});
