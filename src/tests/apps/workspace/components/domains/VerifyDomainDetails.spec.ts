// src/tests/apps/workspace/components/domains/VerifyDomainDetails.spec.ts

import VerifyDomainDetails from '@/apps/workspace/components/domains/VerifyDomainDetails.vue';
import { setDomainValidationStrategy } from '@tests/support/domainValidationStrategy';
import { createTestI18n } from '@tests/setup';
import { flushPromises, mount, type VueWrapper } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

const mockVerifyDomain = vi.fn();
const mockIsLoading = ref(false);
const mockError = ref<{ message: string } | null>(null);

vi.mock('@/shared/composables/useDomainsManager', () => ({
  useDomainsManager: () => ({
    verifyDomain: mockVerifyDomain,
    isLoading: mockIsLoading,
    error: mockError,
  }),
}));

const mockCanonicalDomain = ref('secrets.example.com');
const mockSiteHost = ref('secrets.example.com');

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

vi.mock('@/utils/features', async (importOriginal) => {
  const { featuresForStrategy } = await import('@tests/support/domainValidationStrategy');
  return featuresForStrategy(await importOriginal<typeof import('@/utils/features')>());
});

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name'],
  },
}));

// i18n pass-through: keys render as-is (ADR-014).
const i18n = createTestI18n();

const createDomain = (overrides = {}) => ({
  extid: 'dm-test-extid',
  display_domain: 'test.example.com',
  base_domain: 'example.com',
  trd: 'test',
  is_apex: false,
  verified: false,
  txt_validation_host: '_onetime-challenge-abc123.test',
  txt_validation_value: 'f00dfeed',
  vhost: null,
  ...overrides,
});

const clusters = {
  approximated: {
    type: 'approximated',
    validation_strategy: 'approximated',
    proxy_ip: '192.0.2.10',
    proxy_host: 'proxy.approximated.example',
    proxy_name: 'Approximated',
  },
  // Features.safe_dump with no Approximated proxy configured.
  caddy_on_demand: {
    type: 'caddy_on_demand',
    validation_strategy: 'caddy_on_demand',
    proxy_ip: null,
    proxy_host: null,
    proxy_name: null,
  },
  passthrough: {
    type: 'passthrough',
    validation_strategy: 'passthrough',
    proxy_ip: null,
    proxy_host: null,
    proxy_name: null,
  },
};

const mountComponent = (props: Record<string, unknown> = {}) =>
  mount(VerifyDomainDetails, {
    props: {
      domain: createDomain(),
      cluster: clusters.caddy_on_demand,
      withVerifyCTA: true,
      ...props,
    } as never,
    global: { plugins: [i18n] },
  });

interface FieldRow {
  label: string;
  value: string;
  appendix: string | undefined;
}

/** The DetailField rows inside `root`, as their label / value / appendix props. */
const fieldsOf = (root: Pick<VueWrapper, 'findAllComponents'>): FieldRow[] =>
  root.findAllComponents({ name: 'DetailField' }).map((f) => ({
    label: f.props('label') as string,
    value: f.props('value') as string,
    appendix: f.props('appendix') as string | undefined,
  }));

describe('VerifyDomainDetails', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsLoading.value = false;
    mockError.value = null;
    mockCanonicalDomain.value = 'secrets.example.com';
    mockSiteHost.value = 'secrets.example.com';
    setDomainValidationStrategy('caddy_on_demand');
  });

  describe.each(Object.keys(clusters) as (keyof typeof clusters)[])('under %s', (strategy) => {
    it('renders the TXT record host and value', () => {
      const wrapper = mountComponent({ cluster: clusters[strategy] });

      expect(fieldsOf(wrapper).slice(0, 3)).toEqual([
        { label: 'web.COMMON.type', value: 'TXT', appendix: undefined },
        {
          label: 'web.COMMON.host',
          value: '_onetime-challenge-abc123.test',
          appendix: '.example.com',
        },
        { label: 'web.COMMON.value', value: 'f00dfeed', appendix: undefined },
      ]);
    });

    it('renders the verify button', () => {
      const wrapper = mountComponent({ cluster: clusters[strategy] });

      expect(wrapper.find('[data-testid="verify-domain-details-button"]').exists()).toBe(true);
    });
  });

  describe('address record (step 2)', () => {
    const addressFields = (wrapper: ReturnType<typeof mountComponent>) =>
      fieldsOf(wrapper.find('[data-testid="verify-address-record"]'));

    it('approximated subdomain: CNAME to the proxy host', () => {
      const wrapper = mountComponent({ cluster: clusters.approximated });

      expect(wrapper.text()).toContain('web.domains.2_create_the_cname_record');
      expect(addressFields(wrapper)).toEqual([
        { label: 'web.COMMON.type', value: 'CNAME', appendix: undefined },
        { label: 'web.COMMON.host', value: 'test', appendix: '.example.com' },
        { label: 'web.COMMON.value', value: 'proxy.approximated.example', appendix: undefined },
      ]);
    });

    it('approximated apex: A record to the proxy IP', () => {
      const wrapper = mountComponent({
        cluster: clusters.approximated,
        domain: createDomain({ is_apex: true, trd: '' }),
      });

      expect(wrapper.text()).toContain('web.domains.2_create_the_a_record');
      expect(addressFields(wrapper)).toEqual([
        { label: 'web.COMMON.type', value: 'A', appendix: undefined },
        { label: 'web.COMMON.host', value: '@', appendix: 'example.com' },
        { label: 'web.COMMON.value', value: '192.0.2.10', appendix: undefined },
      ]);
      expect(wrapper.text()).not.toContain('web.domains.dns.apex_notice');
    });

    it('caddy_on_demand subdomain: CNAME to the canonical domain', () => {
      const wrapper = mountComponent();

      expect(wrapper.text()).toContain('web.domains.2_create_the_cname_record');
      expect(addressFields(wrapper)).toEqual([
        { label: 'web.COMMON.type', value: 'CNAME', appendix: undefined },
        { label: 'web.COMMON.host', value: 'test', appendix: '.example.com' },
        { label: 'web.COMMON.value', value: 'secrets.example.com', appendix: undefined },
      ]);
    });

    it('caddy_on_demand apex: ALIAS/ANAME to the canonical domain, with the apex notice', () => {
      const wrapper = mountComponent({ domain: createDomain({ is_apex: true, trd: '' }) });

      expect(wrapper.text()).toContain('web.domains.2_create_the_alias_record');
      expect(wrapper.text()).toContain('web.domains.dns.apex_notice');
      expect(addressFields(wrapper)).toEqual([
        { label: 'web.COMMON.type', value: 'ALIAS / ANAME', appendix: undefined },
        { label: 'web.COMMON.host', value: '@', appendix: 'example.com' },
        { label: 'web.COMMON.value', value: 'secrets.example.com', appendix: undefined },
      ]);
    });

    it("caddy_on_demand never shows Approximated's proxy targets, even if they are configured", () => {
      const cluster = {
        ...clusters.caddy_on_demand,
        proxy_ip: '192.0.2.10',
        proxy_host: 'proxy.approximated.example',
      };

      for (const domain of [createDomain(), createDomain({ is_apex: true, trd: '' })]) {
        const wrapper = mountComponent({ cluster, domain });
        const values = fieldsOf(wrapper).map((f) => f.value);

        expect(values).not.toContain('192.0.2.10');
        expect(values).not.toContain('proxy.approximated.example');
      }
    });

    it('uses the bootstrap strategy when the domains API sent no cluster', () => {
      setDomainValidationStrategy('caddy_on_demand');
      const wrapper = mountComponent({ cluster: null });

      expect(addressFields(wrapper)[2].value).toBe('secrets.example.com');
    });
  });

  describe('verify action', () => {
    it('is hidden when withVerifyCTA is false', () => {
      const wrapper = mountComponent({ withVerifyCTA: false });

      expect(wrapper.find('[data-testid="verify-domain-details-button"]').exists()).toBe(false);
    });

    it('runs the check and emits domainVerify with the result', async () => {
      const result = { record: { extid: 'dm-test-extid' } };
      mockVerifyDomain.mockResolvedValueOnce(result);

      const wrapper = mountComponent();
      await wrapper.find('[data-testid="verify-domain-details-button"]').trigger('click');
      await flushPromises();

      expect(mockVerifyDomain).toHaveBeenCalledWith('dm-test-extid');
      expect(wrapper.emitted('domainVerify')).toEqual([[result]]);
    });

    it('emits nothing when the check returned no result', async () => {
      mockVerifyDomain.mockResolvedValueOnce(null);

      const wrapper = mountComponent();
      await wrapper.find('[data-testid="verify-domain-details-button"]').trigger('click');
      await flushPromises();

      expect(wrapper.emitted('domainVerify')).toBeUndefined();
    });
  });

  // The refreshed record reads the same after "could not tell" as after "no":
  // an indeterminate TXT check leaves `verified` as it was. The alert is where
  // the customer sees the difference.
  describe('verify outcome alert', () => {
    const outcomeAlert = '[data-testid="verify-outcome-alert"]';

    const verifyWith = async (details: Record<string, unknown> | undefined) => {
      mockVerifyDomain.mockResolvedValueOnce({ record: { extid: 'dm-test-extid' }, details });
      const wrapper = mountComponent();
      await wrapper.find('[data-testid="verify-domain-details-button"]').trigger('click');
      await flushPromises();
      return wrapper;
    };

    it('validated: the success text, and no outcome alert', async () => {
      const wrapper = await verifyWith({ dns_outcome: 'validated', dns_indeterminate: false });

      expect(wrapper.text()).toContain('web.domains.domain_verification_initiated_successfully');
      expect(wrapper.find(outcomeAlert).exists()).toBe(false);
    });

    it.each(['indeterminate', 'confirmation_expired'])(
      '%s: a warning that the check could not be completed, not a success',
      async (dns_outcome) => {
        const wrapper = await verifyWith({ dns_outcome, dns_indeterminate: true });
        const alert = wrapper.find(outcomeAlert);

        expect(alert.text()).toBe('web.domains.verify_outcome.indeterminate');
        expect(alert.attributes('data-severity')).toBe('warning');
        expect(alert.attributes('role')).toBe('status');
        expect(wrapper.text()).not.toContain(
          'web.domains.domain_verification_initiated_successfully'
        );
        expect(wrapper.text()).not.toContain('web.domains.verify_outcome.record_not_found');
      }
    );

    it('failed: the record was not found, not a success', async () => {
      const wrapper = await verifyWith({ dns_outcome: 'failed', dns_indeterminate: false });
      const alert = wrapper.find(outcomeAlert);

      expect(alert.text()).toBe('web.domains.verify_outcome.record_not_found');
      expect(alert.attributes('data-severity')).toBe('info');
      expect(wrapper.text()).not.toContain(
        'web.domains.domain_verification_initiated_successfully'
      );
      expect(wrapper.text()).not.toContain('web.domains.verify_outcome.indeterminate');
    });

    it('a response without an outcome keeps the neutral success text', async () => {
      const wrapper = await verifyWith(undefined);

      expect(wrapper.text()).toContain('web.domains.domain_verification_initiated_successfully');
      expect(wrapper.find(outcomeAlert).exists()).toBe(false);
    });

    it('a later check replaces the earlier alert', async () => {
      vi.useFakeTimers();
      try {
        const wrapper = await verifyWith({ dns_outcome: 'indeterminate', dns_indeterminate: true });
        expect(wrapper.find(outcomeAlert).exists()).toBe(true);

        // The button re-enables 3 seconds after a check.
        await vi.advanceTimersByTimeAsync(3000);
        mockVerifyDomain.mockResolvedValueOnce({
          record: { extid: 'dm-test-extid' },
          details: { dns_outcome: 'validated', dns_indeterminate: false },
        });
        await wrapper.find('[data-testid="verify-domain-details-button"]').trigger('click');
        await flushPromises();

        expect(mockVerifyDomain).toHaveBeenCalledTimes(2);
        expect(wrapper.find(outcomeAlert).exists()).toBe(false);
        expect(wrapper.text()).toContain('web.domains.domain_verification_initiated_successfully');
      } finally {
        vi.useRealTimers();
      }
    });
  });

  describe('accessibility', () => {
    it('the verify action is a real button with a text label', () => {
      const button = mountComponent().find('[data-testid="verify-domain-details-button"]');

      expect(button.element.tagName).toBe('BUTTON');
      expect(button.attributes('type')).toBe('button');
      expect(button.text()).toBe('web.domains.verify_domain');
      expect(button.attributes('aria-busy')).toBe('false');
      expect(button.find('.o-icon').exists()).toBe(true);
    });

    it('is disabled, busy and relabelled while the check runs', async () => {
      mockIsLoading.value = true;
      const button = mountComponent().find('[data-testid="verify-domain-details-button"]');

      expect(button.attributes('disabled')).toBeDefined();
      expect(button.attributes('aria-busy')).toBe('true');
      expect(button.text()).toBe('web.COMMON.processing');
    });

    it('every record row keeps a labelled copy button', () => {
      const wrapper = mountComponent();
      const rows = wrapper.findAllComponents({ name: 'DetailField' });

      // TXT type/host/value + address type/host/value.
      expect(rows).toHaveLength(6);
      for (const row of rows) {
        const copy = row.find('button');
        expect(copy.exists()).toBe(true);
        expect(copy.attributes('aria-label')).toBe('web.LABELS.copy_to_clipboard');
      }
    });

    it('the TXT value copy button copies the challenge value', () => {
      const wrapper = mountComponent();
      const copyButtons = wrapper.findAllComponents({ name: 'CopyButton' });

      expect(copyButtons[1].props('text')).toBe('_onetime-challenge-abc123.test');
      expect(copyButtons[2].props('text')).toBe('f00dfeed');
    });

    it('steps are an ordered list with a heading each', () => {
      const wrapper = mountComponent();

      expect(wrapper.find('ol').findAll('li')).toHaveLength(3);
      expect(wrapper.find('ol').findAll('li h3')).toHaveLength(3);
    });
  });
});
