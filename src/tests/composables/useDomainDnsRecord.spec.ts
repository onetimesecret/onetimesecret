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
      const r = record(
        { is_apex: false, trd: '', base_domain: 'example.com' },
        cluster('passthrough')
      );

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

// The record is created under the A-label form of the name: host and zone come
// from display_domain_ascii, split by the label counts of trd and base_domain.
// The copy button copies the host. The typed spelling is a hint beside it.
describe('useDomainDnsRecord A-label name (display_domain_ascii)', () => {
  beforeEach(() => {
    setDomainValidationStrategy('passthrough');
  });

  const named = (domain: object) => {
    const r = useDomainDnsRecord(
      () => domain as never,
      () => cluster('passthrough') as never
    );
    return {
      host: r.recordHost.value,
      appendix: r.recordHostAppendix.value,
      displayName: r.recordDisplayName.value,
    };
  };

  it('Unicode subdomain: the A-label host, the zone, and the typed spelling as a hint', () => {
    expect(
      named({
        is_apex: false,
        trd: 'bücher',
        base_domain: 'example.com',
        display_domain: 'bücher.example.com',
        display_domain_ascii: 'xn--bcher-kva.example.com',
      })
    ).toEqual({
      host: 'xn--bcher-kva',
      appendix: '.example.com',
      displayName: 'bücher.example.com',
    });
  });

  it('Unicode registrable domain: the zone in A-label form', () => {
    expect(
      named({
        is_apex: false,
        trd: 'secrets',
        base_domain: 'bücher.de',
        display_domain: 'secrets.bücher.de',
        display_domain_ascii: 'secrets.xn--bcher-kva.de',
      })
    ).toEqual({
      host: 'secrets',
      appendix: '.xn--bcher-kva.de',
      displayName: 'secrets.bücher.de',
    });
  });

  it("Unicode apex: '@' and the A-label zone, undotted", () => {
    expect(
      named({
        is_apex: true,
        trd: '',
        base_domain: 'bücher.de',
        display_domain: 'bücher.de',
        display_domain_ascii: 'xn--bcher-kva.de',
      })
    ).toEqual({ host: '@', appendix: 'xn--bcher-kva.de', displayName: 'bücher.de' });
  });

  it('ASCII subdomain: as before, no hint', () => {
    expect(
      named({
        ...subdomain,
        display_domain: 'test.example.com',
        display_domain_ascii: 'test.example.com',
      })
    ).toEqual({ host: 'test', appendix: '.example.com', displayName: null });
  });

  it('ASCII apex: as before, no hint', () => {
    expect(
      named({ ...apex, display_domain: 'example.com', display_domain_ascii: 'example.com' })
    ).toEqual({ host: '@', appendix: 'example.com', displayName: null });
  });

  it('a typed spelling that differs only in case is not a different name', () => {
    expect(
      named({
        ...subdomain,
        trd: 'Test',
        display_domain: 'Test.Example.com',
        display_domain_ascii: 'test.example.com',
      })
    ).toEqual({ host: 'test', appendix: '.example.com', displayName: null });
  });

  it('multi-label subdomain: every subdomain label stays in the host', () => {
    expect(
      named({
        is_apex: false,
        trd: 'a.bücher',
        base_domain: 'example.co.uk',
        display_domain: 'a.bücher.example.co.uk',
        display_domain_ascii: 'a.xn--bcher-kva.example.co.uk',
      })
    ).toMatchObject({ host: 'a.xn--bcher-kva', appendix: '.example.co.uk' });
  });

  it('a name that does not split against trd and base_domain: the full A-label name', () => {
    // U+3002 separates labels like "." and is mapped to it on conversion.
    expect(
      named({
        is_apex: false,
        trd: 'bücher',
        base_domain: 'example\u3002com',
        display_domain: 'bücher.example\u3002com',
        display_domain_ascii: 'xn--bcher-kva.example.com',
      })
    ).toEqual({
      host: 'xn--bcher-kva.example.com',
      appendix: '',
      displayName: 'bücher.example\u3002com',
    });
  });

  describe('without display_domain_ascii: the typed trd and base_domain, no hint', () => {
    it.each([
      ['null (no A-label form)', null],
      ['absent (older payload)', undefined],
    ])('%s', (_label, display_domain_ascii) => {
      const unicode = {
        is_apex: false,
        trd: 'bücher',
        base_domain: 'example.com',
        display_domain: 'bücher.example.com',
        display_domain_ascii,
      };
      const unicodeApex = {
        is_apex: true,
        trd: '',
        base_domain: 'bücher.de',
        display_domain: 'bücher.de',
        display_domain_ascii,
      };

      expect(named(unicode)).toEqual({
        host: 'bücher',
        appendix: '.example.com',
        displayName: null,
      });
      expect(named(unicodeApex)).toEqual({ host: '@', appendix: 'bücher.de', displayName: null });
    });
  });
});
