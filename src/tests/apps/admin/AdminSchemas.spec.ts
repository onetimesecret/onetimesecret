// src/tests/apps/admin/AdminSchemas.spec.ts

import AdminSchemas from '@/apps/admin/views/AdminSchemas.vue';
import * as checker from '@/schemas/check';
import * as diagnostics from '@/services/diagnostics.service';
import sourceCopy from '../../../../locales/content/en/admin-schemas.json';
import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createI18n } from 'vue-i18n';

const messages = Object.fromEntries(
  Object.entries(sourceCopy).map(([key, entry]) => [key, entry.text])
);

function mountView() {
  return mount(AdminSchemas, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          flatJson: true,
          messages: { en: messages as never },
        }),
      ],
    },
  });
}

const feedback = { msg: 'private-payload-value', stamp: 1700000000 };

describe('AdminSchemas', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    wrapper = mountView();
  });
  afterEach(() => {
    wrapper.unmount();
    vi.restoreAllMocks();
  });

  async function select(name = 'shapes/feedback') {
    await wrapper.get(`[data-schema="${name}"]`).trigger('click');
  }

  async function validate(payload: unknown) {
    await wrapper.get('textarea').setValue(JSON.stringify(payload));
    await wrapper.get('form').trigger('submit');
  }

  it('lists all CLI schemas, including versions, internal responses, config and aliases', () => {
    const listed = wrapper
      .findAll('[data-schema]')
      .map((button) => button.attributes('data-schema'));
    expect(listed).toEqual([...checker.allSchemas().keys()].sort());
    expect(listed).toEqual(
      expect.arrayContaining([
        'v1.v1SecretReveal',
        'v2.receipt',
        'v3.secret',
        'internal.colonelSecrets',
        'incoming.validateRecipient',
        'shapes/secret',
        'config/auth',
        'api/v3/secret-response',
      ])
    );
    expect(wrapper.get('[data-testid="selected-schema"]').text()).toBe('v3.secret');
  });

  it('filters schema names without changing the selected schema', async () => {
    await wrapper.get('#schema-search').setValue('  V3.SECRET  ');
    expect(wrapper.findAll('[data-schema]').map((b) => b.text())).toEqual([
      'v3.secret',
      'v3.secretList',
    ]);
    await wrapper.get('#schema-search').setValue('no-such-schema');
    expect(wrapper.findAll('[data-schema]')).toHaveLength(0);
    expect(wrapper.text()).toContain('No schemas match this filter.');
    expect(wrapper.get('[data-testid="selected-schema"]').text()).toBe('v3.secret');
  });

  it('validates original wire input locally without uploading or saving it', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const storageSpy = vi.spyOn(Storage.prototype, 'setItem');
    await select();
    await validate(feedback);
    const report = wrapper.get('[data-testid="schema-report"]');
    expect(report.text()).toContain('Valid against shapes/feedback');
    expect(report.text()).not.toContain(feedback.msg);
    expect(wrapper.find('[data-testid="schema-candidates"]').exists()).toBe(false);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(storageSpy).not.toHaveBeenCalled();
  });

  it.each(['shapes/organization', 'shapes/feedback'])(
    'suppresses payload-bearing schema diagnostics when checking %s, including closest matches',
    async (schema) => {
      const warnings = vi.spyOn(console, 'warn').mockImplementation(() => {});
      const captures = vi.spyOn(diagnostics, 'captureMessage');
      await select(schema);
      await validate({ entitlements: [`private-ui-entitlement-${schema}`] });
      expect(wrapper.find('[data-testid="schema-report"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="schema-candidates"]').exists()).toBe(true);
      expect(warnings).not.toHaveBeenCalled();
      expect(captures).not.toHaveBeenCalled();
    }
  );

  it('warns about undeclared keys even when the payload is valid', async () => {
    await select();
    await validate({ ...feedback, extra: 'undeclared-private-value' });
    const report = wrapper.get('[data-testid="schema-report"]');
    expect(report.text()).toContain('Valid against shapes/feedback');
    expect(report.text()).toContain('Undeclared: extra');
    expect(report.text()).not.toContain('undeclared-private-value');
  });

  it('groups missing fields, type errors and undeclared fields, hiding values', async () => {
    await select();
    await validate({ stamp: 'sensitive-wrong-type', extra: 'private-extra' });
    const report = wrapper.get('[data-testid="schema-report"]');
    expect(report.text()).toContain('Invalid against shapes/feedback: 2 issues');
    expect(report.text()).toContain('Missing: msg');
    expect(report.text()).toContain('stamp: expected number, got string(20)');
    expect(report.text()).toContain('Undeclared: extra');
    expect(report.text()).not.toContain('sensitive-wrong-type');
    expect(report.text()).not.toContain('private-extra');
    expect(wrapper.find('[data-testid="schema-candidates"]').exists()).toBe(true);
  });

  it('selects a closest schema without changing the payload or retaining a stale report', async () => {
    await select();
    await validate({ stamp: 'wrong-type' });
    const payload = (wrapper.get('textarea').element as HTMLTextAreaElement).value;
    const suggestion = wrapper.get('[data-testid="schema-candidates"] button');
    const name = suggestion.text();
    await suggestion.trigger('click');
    expect(wrapper.get('[data-testid="selected-schema"]').text()).toBe(name);
    expect((wrapper.get('textarea').element as HTMLTextAreaElement).value).toBe(payload);
    expect(wrapper.find('[data-testid="schema-report"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="schema-candidates"]').exists()).toBe(false);
  });

  it('does not echo JSON syntax errors, which can contain payload fragments', async () => {
    await wrapper.get('textarea').setValue('{"secret":"do-not-echo-this"');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.get('[data-testid="schema-input-error"]').text()).toBe(
      'Invalid JSON. Check the syntax and try again.'
    );
    expect(wrapper.get('[data-testid="schema-input-error"]').text()).not.toContain(
      'do-not-echo-this'
    );
    expect(wrapper.find('[data-testid="schema-report"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="schema-candidates"]').exists()).toBe(false);
  });

  it('handles schemas that throw without rendering exception content', async () => {
    vi.spyOn(checker, 'checkPayload').mockImplementation(() => {
      throw new Error('sensitive-transform-value');
    });
    await validate({});
    const error = wrapper.get('[data-testid="schema-input-error"]');
    expect(error.text()).toContain('This schema could not check the payload.');
    expect(error.text()).not.toContain('sensitive-transform-value');
    expect(wrapper.find('[data-testid="schema-report"]').exists()).toBe(false);
  });

  it('invalidates reports when either the payload or selected schema changes', async () => {
    await select();
    await validate(feedback);
    await wrapper.get('textarea').setValue('{}');
    expect(wrapper.find('[data-testid="schema-report"]').exists()).toBe(false);
    await validate(feedback);
    await select('config/auth');
    expect(wrapper.find('[data-testid="schema-report"]').exists()).toBe(false);
  });

  it('clears the payload, error and result while keeping the selected schema', async () => {
    await select();
    await validate({});
    await wrapper.get('[data-testid="clear-payload"]').trigger('click');
    expect((wrapper.get('textarea').element as HTMLTextAreaElement).value).toBe('');
    expect(wrapper.find('[data-testid="schema-report"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="schema-candidates"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="schema-input-error"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="selected-schema"]').text()).toBe('shapes/feedback');
    expect(wrapper.get('[data-testid="validate-payload"]').attributes('disabled')).toBeDefined();
  });

  it('accepts non-object JSON when the chosen schema does', async () => {
    await select('shapes/secret-state');
    await validate('new');
    expect(wrapper.get('[data-testid="schema-report"]').text()).toContain(
      'Valid against shapes/secret-state'
    );
  });
});
