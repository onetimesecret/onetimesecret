// src/tests/composables/useDomainDnsRecord.spec.ts

import { useDomainDnsRecord } from '@/shared/composables/useDomainDnsRecord';
import {
  DOMAIN_VALIDATION_STRATEGIES,
  setDomainValidationStrategy,
} from '@tests/support/domainValidationStrategy';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

const mockCanonicalDomain = ref('secrets.example.com');
const mockSiteHost = ref('host.example.com');

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({
    canonical_domain: mockCanonicalDomain,
    site_host: mockSiteHost,
  }),
}));

vi.mock('pinia', async (importOriginal) => ({
  ...(await importOriginal<typeof import('pinia')>()),
  storeToRefs: (store: Record<string, unknown>) => store,
}));

// Bootstrap-level strategy, used only when the caller has no cluster.
vi.mock('@/utils/features', async (importOriginal) => {
  const { featuresForStrategy } = await import('@tests/support/domainValidationStrategy');
  return featuresForStrategy(await importOriginal<typeof import('@/utils/features')>());
});

const subdomain = { is_apex: false, trd: 'test', base_domain: 'example.com' };
const apex = { is_apex: true, trd: '', base_domain: 'example.com' };

const cluster = (validation_strategy: string, overrides = {}) => ({
  validation_strategy,
  proxy_ip: '192.0.2.10',
  proxy_host: 'proxy.approximated.example',
  ...overrides,
});

const record = (domain: object, c?: object | null) => {
  const r = useDomainDnsRecord(
    () => domain as never,
    () => c as never
  );
  return {
    kind: r.kind.value,
    type: r.recordType.value,
    host: r.recordHost.value,
    appendix: r.recordHostAppendix.value,
    target: r.recordTarget.value,
    proxy: r.usesApproximatedProxy.value,
  };
};

describe('useDomainDnsRecord', () => {
  beforeEach(() => {
    mockCanonicalDomain.value = 'secrets.example.com';
    mockSiteHost.value = 'host.example.com';
    setDomainValidationStrategy('passthrough');
  });

  describe('approximated: the record points at the Approximated proxy', () => {
    it('gives a subdomain a CNAME to proxy_host', () => {
      expect(record(subdomain, cluster('approximated'))).toEqual({
        kind: 'cname',
        type: 'CNAME',
        host: 'test',
        appendix: '.example.com',
        target: 'proxy.approximated.example',
        proxy: true,
      });
    });

    it('gives an apex domain an A record to proxy_ip', () => {
      expect(record(apex, cluster('approximated'))).toEqual({
        kind: 'a',
        type: 'A',
        host: '@',
        appendix: 'example.com',
        target: '192.0.2.10',
        proxy: true,
      });
    });

    it('renders an empty target, not the canonical domain, when the proxy is not configured', () => {
      const r = record(subdomain, cluster('approximated', { proxy_host: null }));

      expect(r.target).toBe('');
    });
  });

  describe.each(['caddy_on_demand', 'passthrough'])(
    '%s: the record points at this install',
    (strategy) => {
      it('gives a subdomain a CNAME to the canonical domain', () => {
        expect(record(subdomain, cluster(strategy))).toEqual({
          kind: 'cname',
          type: 'CNAME',
          host: 'test',
          appendix: '.example.com',
          target: 'secrets.example.com',
          proxy: false,
        });
      });

      it('gives an apex domain ALIAS/ANAME to the canonical domain', () => {
        expect(record(apex, cluster(strategy))).toEqual({
          kind: 'alias',
          type: 'ALIAS / ANAME',
          host: '@',
          appendix: 'example.com',
          target: 'secrets.example.com',
          proxy: false,
        });
      });

      it('never reads the Approximated proxy fields, even when they are set', () => {
        const r = record(apex, cluster(strategy));

        expect(r.target).not.toBe('192.0.2.10');
        expect(record(subdomain, cluster(strategy)).target).not.toBe('proxy.approximated.example');
      });

      it('falls back to the site host, then to an empty string', () => {
        mockCanonicalDomain.value = '';
        expect(record(subdomain, cluster(strategy)).target).toBe('host.example.com');

        mockSiteHost.value = '';
        expect(record(subdomain, cluster(strategy)).target).toBe('');
      });
    }
  );

  describe('without a cluster', () => {
    it.each(DOMAIN_VALIDATION_STRATEGIES)('takes %s from the bootstrap snapshot', (strategy) => {
      setDomainValidationStrategy(strategy);

      expect(record(subdomain, null).proxy).toBe(strategy === 'approximated');
    });

    it('prefers the cluster over the bootstrap snapshot', () => {
      setDomainValidationStrategy('approximated');

      expect(record(subdomain, cluster('caddy_on_demand')).proxy).toBe(false);
    });
  });

  describe('host', () => {
    it("reads '@' for a non-apex record with a blank trd, with the dotted appendix", () => {
      const r = record({ is_apex: false, trd: '', base_domain: 'example.com' }, cluster('passthrough'));

      expect(r.host).toBe('@');
      expect(r.appendix).toBe('.example.com');
    });

    it('has no appendix without a base domain, and tolerates a null domain', () => {
      expect(record({ is_apex: false, trd: 'a' }, cluster('passthrough')).appendix).toBe('');

      const r = useDomainDnsRecord(() => null);
      expect(r.recordHost.value).toBe('@');
      expect(r.kind.value).toBe('cname');
    });
  });
});
