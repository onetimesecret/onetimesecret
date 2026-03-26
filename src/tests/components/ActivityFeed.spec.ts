// src/tests/components/ActivityFeed.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import ActivityFeed from '@/shared/components/ui/ActivityFeed.vue';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="mock-icon"></span>',
    props: ['collection', 'name'],
  },
}));

vi.mock('@headlessui/vue', () => ({
  Listbox: {
    name: 'Listbox',
    template: '<div class="listbox"><slot /></div>',
    props: ['as', 'modelValue'],
  },
  ListboxButton: {
    name: 'ListboxButton',
    template: '<button class="listbox-button"><slot /></button>',
    props: ['class'],
  },
  ListboxLabel: {
    name: 'ListboxLabel',
    template: '<label class="listbox-label"><slot /></label>',
    props: ['class'],
  },
  ListboxOption: {
    name: 'ListboxOption',
    template: '<li class="listbox-option"><slot :active="false" /></li>',
    props: ['as', 'value'],
  },
  ListboxOptions: {
    name: 'ListboxOptions',
    template: '<ul class="listbox-options"><slot /></ul>',
    props: ['class'],
  },
}));

const sampleActivity = [
  { id: 1, type: 'created', person: { name: 'Alice' }, date: '1d ago', dateTime: '2025-01-01T10:00' },
  { id: 2, type: 'viewed', person: { name: 'Bob' }, date: '2d ago', dateTime: '2025-01-02T11:00' },
  {
    id: 3,
    type: 'commented',
    person: { name: 'Carol', imageUrl: '/img/carol.png' },
    comment: 'Test comment',
    date: '3d ago',
    dateTime: '2025-01-03T12:00',
  },
];

describe('ActivityFeed', () => {
  it('renders empty list when no activity prop is passed', () => {
    const wrapper = mount(ActivityFeed);
    const activityList = wrapper.find('ul[role="list"]');
    const listItems = activityList.findAll(':scope > li');
    expect(listItems.length).toBe(0);
  });

  it('renders activity items when passed via props', () => {
    const wrapper = mount(ActivityFeed, {
      props: { activity: sampleActivity },
    });
    const activityList = wrapper.find('ul[role="list"]');
    const listItems = activityList.findAll(':scope > li');
    expect(listItems.length).toBe(sampleActivity.length);
  });

  it('renders person names in activity items', () => {
    const wrapper = mount(ActivityFeed, {
      props: { activity: sampleActivity },
    });
    expect(wrapper.text()).toContain('Alice');
    expect(wrapper.text()).toContain('Bob');
    expect(wrapper.text()).toContain('Carol');
  });

  it('renders comment text for commented activity type', () => {
    const wrapper = mount(ActivityFeed, {
      props: { activity: sampleActivity },
    });
    expect(wrapper.text()).toContain('Test comment');
  });

  it('does not render avatar image when avatarUrl is empty', () => {
    const wrapper = mount(ActivityFeed);
    const formImg = wrapper.find('.mt-6 img');
    expect(formImg.exists()).toBe(false);
  });

  it('renders avatar image when avatarUrl is provided', () => {
    const wrapper = mount(ActivityFeed, {
      props: { avatarUrl: '/img/avatar.png' },
    });
    const formImg = wrapper.find('.mt-6 img');
    expect(formImg.exists()).toBe(true);
    expect(formImg.attributes('src')).toBe('/img/avatar.png');
  });

  it('shows default mood icon when selected mood value is empty string', () => {
    const wrapper = mount(ActivityFeed);
    // The default selected mood is moods[5] with value: ''
    // v-if="!selected.value" should show the face-smile icon
    const button = wrapper.find('.listbox-button');
    expect(button.exists()).toBe(true);
    // The first span (default state) should be visible
    const spans = button.findAll('span > span');
    // With falsy check, the default icon span renders
    expect(spans.length).toBeGreaterThanOrEqual(1);
  });
});
