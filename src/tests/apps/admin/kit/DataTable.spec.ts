// src/tests/apps/admin/kit/DataTable.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Component } from 'vue';

import DataTableComponent from '@/apps/admin/components/kit/DataTable.vue';
import type { DataTableColumn, SortState } from '@/apps/admin/components/kit/types';
import { createTestI18n } from '@tests/setup';

// DataTable is a generic component (`<script setup generic="T">`). Vue Test Utils
// infers the type parameter as `unknown` at the mount site, which then rejects a
// concretely-typed `columns`/`rowKey` (e.g. `rowKey: 'id'` — `keyof unknown` is
// `never`). Cast to a plain Component to sidestep that generic-inference friction;
// the runtime component is unchanged and prop behaviour is still asserted.
const DataTable = DataTableComponent as unknown as Component;

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

interface Row {
  id: string;
  email: string;
  secrets: number;
}

const rows: Row[] = [
  { id: 'a', email: 'alice@example.com', secrets: 3 },
  { id: 'b', email: 'bob@example.com', secrets: 7 },
];

const columns: DataTableColumn<Row>[] = [
  { key: 'email', label: 'Email', sortable: true },
  { key: 'secrets', label: 'Secrets', align: 'right', accessor: (r) => `${r.secrets} secrets` },
];

const i18n = createTestI18n();

describe('DataTable (config-driven table)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  const mountTable = (props: Record<string, unknown> = {}, slots: Record<string, string> = {}) =>
    mount(DataTable, {
      props: { columns, rows, rowKey: 'id', ...props },
      slots,
      global: { plugins: [i18n] },
    });

  it('renders one <th> per column from config (no per-view duplication)', () => {
    wrapper = mountTable();
    const headers = wrapper.findAll('thead th');
    expect(headers).toHaveLength(2);
    expect(headers[0].text()).toContain('Email');
    expect(headers[1].text()).toContain('Secrets');
  });

  it('renders a row per record with default and accessor cell values', () => {
    wrapper = mountTable();
    const bodyRows = wrapper.findAll('tbody tr');
    expect(bodyRows).toHaveLength(2);
    expect(bodyRows[0].text()).toContain('alice@example.com');
    // accessor column derives its text
    expect(bodyRows[0].text()).toContain('3 secrets');
  });

  it('applies alignment classes from the column config', () => {
    wrapper = mountTable();
    const secondHeader = wrapper.findAll('thead th')[1];
    expect(secondHeader.classes()).toContain('text-right');
  });

  it('renders a sort toggle only for sortable columns', () => {
    wrapper = mountTable();
    const headers = wrapper.findAll('thead th');
    expect(headers[0].find('button').exists()).toBe(true); // sortable
    expect(headers[1].find('button').exists()).toBe(false); // not sortable
  });

  it('emits update:sort ascending on first click of a sortable header', async () => {
    wrapper = mountTable();
    await wrapper.findAll('thead th')[0].find('button').trigger('click');
    expect(wrapper.emitted('update:sort')).toBeTruthy();
    expect(wrapper.emitted('update:sort')![0]).toEqual([{ key: 'email', direction: 'asc' }]);
  });

  it('toggles to descending when the active sort column is clicked again', async () => {
    const sort: SortState = { key: 'email', direction: 'asc' };
    wrapper = mountTable({ sort });
    await wrapper.findAll('thead th')[0].find('button').trigger('click');
    expect(wrapper.emitted('update:sort')![0]).toEqual([{ key: 'email', direction: 'desc' }]);
  });

  it('reflects the controlled sort via aria-sort', () => {
    wrapper = mountTable({ sort: { key: 'email', direction: 'desc' } });
    const headers = wrapper.findAll('thead th');
    expect(headers[0].attributes('aria-sort')).toBe('descending');
    expect(headers[1].attributes('aria-sort')).toBeUndefined(); // not sortable
  });

  it('shows the loading skeleton (not the table) while loading', () => {
    wrapper = mountTable({ loading: true });
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.find('[role="status"]').exists()).toBe(true);
  });

  it('shows the empty state (not the table) when there are no rows', () => {
    wrapper = mountTable({ rows: [] });
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.text()).toContain('web.admin.kit.dataTable.empty');
  });

  it('honors a custom emptyText override', () => {
    wrapper = mountTable({ rows: [], emptyText: 'No customers yet' });
    expect(wrapper.text()).toContain('No customers yet');
  });

  it('supports a per-column cell slot', () => {
    wrapper = mountTable({}, { 'cell-email': '<span class="custom-cell">CUSTOM</span>' });
    expect(wrapper.find('.custom-cell').exists()).toBe(true);
    expect(wrapper.text()).toContain('CUSTOM');
  });

  it('emits row-click with the row only when clickableRows is set', async () => {
    wrapper = mountTable({ clickableRows: true });
    await wrapper.findAll('tbody tr')[1].trigger('click');
    expect(wrapper.emitted('row-click')).toBeTruthy();
    expect(wrapper.emitted('row-click')![0]).toEqual([rows[1]]);
  });

  it('does not emit row-click when clickableRows is false', async () => {
    wrapper = mountTable();
    await wrapper.findAll('tbody tr')[0].trigger('click');
    expect(wrapper.emitted('row-click')).toBeFalsy();
  });

  it('supports an accessor function via a rowKey callback', () => {
    wrapper = mountTable({ rowKey: (r: Row) => `row-${r.id}` });
    expect(wrapper.findAll('tbody tr')).toHaveLength(2);
  });
});
