// src/tests/apps/workspace/components/domains/DnsWidget.spec.ts

import type { DnsRecord, UseDnsWidgetOptions } from '@/shared/composables/useDnsWidget';
import { createTestI18n } from '@tests/setup';
import { mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref, toValue } from 'vue';

import DnsWidget from '@/apps/workspace/components/domains/DnsWidget.vue';

// The records and domain DnsWidget hands to the Approximated widget. The
// composable itself (token, asset loading) is covered in useDnsWidget.spec.ts.
let widgetOptions: UseDnsWidgetOptions | undefined;

vi.mock('@/shared/composables/useDnsWidget', () => ({
  useDnsWidget: (options: UseDnsWidgetOptions) => {
    widgetOptions = options;
    return {
      isLoading: ref(false),
      error: ref(null),
      initWidget: vi.fn(),
      stopWidget: vi.fn(),
    };
  },
}));

const i18n = createTestI18n();

const mountWidget = (props: Record<string, unknown>) =>
  mount(DnsWidget, {
    props: {
      targetAddress: 'proxy.approximated.example',
      txtValidationValue: 'f00dfeed',
      ...props,
    } as never,
    global: { plugins: [i18n] },
  });

const txtRecord = (): DnsRecord | undefined =>
  toValue(widgetOptions?.dnsRecords)?.find((r) => r.type === 'TXT');

describe('DnsWidget', () => {
  beforeEach(() => {
    widgetOptions = undefined;
  });

  // The widget reads `host` relative to `domain`, so the TXT host is the
  // challenge label alone and the widget appends the domain.
  describe('TXT record host', () => {
    it.each([
      [
        'Unicode subdomain (A-label host)',
        'bücher.example.com',
        '_onetime-challenge-abc1234.xn--bcher-kva',
      ],
      ['ASCII subdomain', 'secrets.example.com', '_onetime-challenge-abc1234.secrets'],
      ['multi-label subdomain', 'a.b.example.com', '_onetime-challenge-abc1234.a.b'],
      ['apex (no subdomain)', 'example.com', '_onetime-challenge-abc1234'],
      [
        'Unicode subdomain stored as typed by an earlier version',
        'bücher.example.com',
        '_onetime-challenge-abc1234.bücher',
      ],
    ])('%s: the challenge label', (_label, domain, txtValidationHost) => {
      mountWidget({ domain, txtValidationHost });

      expect(txtRecord()).toEqual({
        type: 'TXT',
        host: '_onetime-challenge-abc1234',
        value: 'f00dfeed',
        ttl: 3600,
      });
    });

    it('keeps the domain as displayed', () => {
      mountWidget({
        domain: 'bücher.example.com',
        txtValidationHost: '_onetime-challenge-abc1234.xn--bcher-kva',
      });

      expect(widgetOptions?.domain).toBe('bücher.example.com');
    });

    it('adds no TXT record without a host or value', () => {
      mountWidget({ domain: 'secrets.example.com', txtValidationHost: undefined });
      expect(txtRecord()).toBeUndefined();

      mountWidget({
        domain: 'secrets.example.com',
        txtValidationHost: '_onetime-challenge-abc1234.secrets',
        txtValidationValue: undefined,
      });
      expect(txtRecord()).toBeUndefined();
    });
  });

  describe('address record', () => {
    it('subdomain: a CNAME at the zone of the domain', () => {
      mountWidget({ domain: 'secrets.example.com', isApex: false });

      expect(toValue(widgetOptions?.dnsRecords)?.[0]).toEqual({
        type: 'CNAME',
        host: '@',
        value: 'proxy.approximated.example',
        ttl: 3600,
      });
    });

    it('apex: an A record', () => {
      mountWidget({ domain: 'example.com', isApex: true, targetAddress: '192.0.2.10' });

      expect(toValue(widgetOptions?.dnsRecords)?.[0]).toMatchObject({
        type: 'A',
        host: '@',
        value: '192.0.2.10',
      });
    });
  });
});
