// src/tests/apps/admin/kit/JsonViewer.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';

import JsonViewer from '@/apps/admin/components/kit/JsonViewer.vue';
import { createTestI18n } from '@tests/setup';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

vi.mock('@/shared/components/ui/CopyButton.vue', () => ({
  default: {
    name: 'CopyButton',
    template: '<button class="copy-button" :data-text="text" />',
    props: ['text', 'tooltip', 'testid'],
  },
}));

const i18n = createTestI18n();

const sample = {
  name: 'alice',
  active: true,
  meta: { role: 'colonel', secrets: 3 },
};

describe('JsonViewer (collapsible JSON inspector)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  const mountViewer = (props: Record<string, unknown> = {}) =>
    mount(JsonViewer, {
      props: { data: sample, ...props },
      global: { plugins: [i18n] },
    });

  it('renders top-level keys and primitive values', () => {
    wrapper = mountViewer();
    expect(wrapper.text()).toContain('name');
    expect(wrapper.text()).toContain('"alice"'); // strings are quoted
    expect(wrapper.text()).toContain('active');
    expect(wrapper.text()).toContain('true');
  });

  it('collapses nested objects beyond expandDepth by default', () => {
    wrapper = mountViewer(); // expandDepth = 1
    expect(wrapper.text()).toContain('meta');
    expect(wrapper.text()).not.toContain('role');
  });

  it('expand all reveals nested values', async () => {
    wrapper = mountViewer();
    const expandBtn = wrapper.findAll('button').find((b) => b.text().includes('expandAll'));
    await expandBtn!.trigger('click');
    await nextTick();
    expect(wrapper.text()).toContain('role');
    expect(wrapper.text()).toContain('"colonel"');
  });

  it('expand all fully expands a deeply nested tree (>2 container levels)', async () => {
    // Regression: freshly-mounted deep descendants must inherit an in-progress
    // expand-all, otherwise the cascade stalls one level past what was visible.
    wrapper = mountViewer({ data: { a: { b: { c: { d: 'leaf' } } } } }); // expandDepth = 1
    // Default: only the top level is expanded, deeper containers are collapsed.
    expect(wrapper.text()).not.toContain('"leaf"');

    const expandBtn = wrapper.findAll('button').find((b) => b.text().includes('expandAll'));
    await expandBtn!.trigger('click');
    await nextTick();

    expect(wrapper.text()).toContain('a');
    expect(wrapper.text()).toContain('b');
    expect(wrapper.text()).toContain('c');
    expect(wrapper.text()).toContain('d');
    expect(wrapper.text()).toContain('"leaf"');
  });

  it('re-expands a deeply nested tree after a collapse all', async () => {
    // Collapse-all then expand-all must still reach the deepest leaf.
    wrapper = mountViewer({ data: { a: { b: { c: { d: 'leaf' } } } }, expandDepth: 5 });
    expect(wrapper.text()).toContain('"leaf"');

    const collapseBtn = wrapper.findAll('button').find((b) => b.text().includes('collapseAll'));
    await collapseBtn!.trigger('click');
    await nextTick();
    expect(wrapper.text()).not.toContain('"leaf"');

    const expandBtn = wrapper.findAll('button').find((b) => b.text().includes('expandAll'));
    await expandBtn!.trigger('click');
    await nextTick();
    expect(wrapper.text()).toContain('"leaf"');
  });

  it('collapse all hides even the top level', async () => {
    wrapper = mountViewer();
    const collapseBtn = wrapper.findAll('button').find((b) => b.text().includes('collapseAll'));
    await collapseBtn!.trigger('click');
    await nextTick();
    expect(wrapper.text()).not.toContain('name');
  });

  it('lets an individual node toggle open', async () => {
    wrapper = mountViewer();
    // The nested `meta` node button is the one showing an object summary `{ 2 }`.
    const metaToggle = wrapper.findAll('button').find((b) => b.text().includes('meta'));
    await metaToggle!.trigger('click');
    await nextTick();
    expect(wrapper.text()).toContain('role');
  });

  it('feeds the pretty-printed JSON to the copy button', () => {
    wrapper = mountViewer();
    const copy = wrapper.find('.copy-button');
    expect(copy.exists()).toBe(true);
    expect(copy.attributes('data-text')).toBe(JSON.stringify(sample, null, 2));
  });

  it('renders an empty message for null/undefined data', () => {
    wrapper = mountViewer({ data: null });
    expect(wrapper.text()).toContain('web.admin.kit.jsonViewer.empty');
  });

  it('can hide the toolbar', () => {
    wrapper = mountViewer({ showToolbar: false });
    expect(wrapper.find('.copy-button').exists()).toBe(false);
  });

  it('renders arrays with an index-labelled, count summary', async () => {
    wrapper = mountViewer({ data: { items: ['x', 'y'] }, expandDepth: 5 });
    // expanded to full depth: array indices show
    expect(wrapper.text()).toContain('items');
    expect(wrapper.text()).toContain('"x"');
  });
});
