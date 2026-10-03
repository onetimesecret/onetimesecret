// src/tests/apps/workspace/components/dashboard/DomainsTableDomainCell.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import DomainsTableDomainCell from '@/apps/workspace/components/dashboard/DomainsTableDomainCell.vue';
import {
  OWNERSHIP_CHECKING_STRATEGIES,
  setDomainValidationStrategy,
} from '@tests/support/domainValidationStrategy';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

// Mock date-fns to avoid locale issues in tests
vi.mock('date-fns', () => ({
  formatDistanceToNow: () => '3 days ago',
}));

// Mock DomainVerificationInfo child component
vi.mock('@/apps/workspace/components/domains/DomainVerificationInfo.vue', () => ({
  default: {
    name: 'DomainVerificationInfo',
    template: '<div class="domain-verification-info" data-testid="verification-info" />',
    props: ['mode', 'domain', 'orgid'],
  },
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock useDomainStatus composable. Tests state the individual flags; the
// composite `needsAttention` is derived here the way the composable derives it
// (covered for real in useDomainStatus.spec.ts).
interface MockDomainStatus {
  isWarning?: boolean;
  isError?: boolean;
  isStale?: boolean;
  needsOwnershipCheck?: boolean;
  displayStatus?: string;
}
const mockUseDomainStatus = vi.fn<() => MockDomainStatus>();
// Set by the blocks that need the label and link derived from a real domain
// record (blob status + verified) instead of stated flags.
let useRealDomainStatus = false;
const withNeedsAttention = (status: MockDomainStatus) => ({
  ...status,
  needsAttention: Boolean(
    status.isWarning || status.isError || status.isStale || status.needsOwnershipCheck
  ),
});
vi.mock('@/shared/composables/useDomainStatus', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/shared/composables/useDomainStatus')>();
  return {
    useDomainStatus: (domain: Parameters<typeof actual.useDomainStatus>[0]) =>
      useRealDomainStatus
        ? actual.useDomainStatus(domain)
        : withNeedsAttention(mockUseDomainStatus()),
  };
});

// Control the install's domain validation strategy. Default to approximated so
// the DNS status assertions below hold; the dedicated blocks cover the others.
// The real capability table is evaluated, not a boolean stub.
vi.mock('@/utils/features', async (importOriginal) => {
  const { featuresForStrategy } = await import('@tests/support/domainValidationStrategy');
  return featuresForStrategy(await importOriginal<typeof import('@/utils/features')>());
});

const mockDomain = {
  identifier: 'domain-123',
  extid: 'dm-test-extid',
  domainid: 'dom_123',
  custid: 'cust_123',
  display_domain: 'test.example.com',
  base_domain: 'example.com',
  subdomain: 'test',
  trd: 'test',
  tld: 'com',
  sld: 'example',
  is_apex: false,
  verified: false,
  resolving: false,
  status: 'pending',
  txt_validation_host: '_challenge.test',
  txt_validation_value: 'verify123',
  vhost: null,
  brand: null,
  created: new Date('2024-01-01'),
  updated: new Date('2024-01-01'),
};

function mountComponent(options: { canEmailConfig?: boolean; domainOverrides?: object } = {}) {
  return mount(DomainsTableDomainCell, {
    props: {
      domain: { ...mockDomain, ...(options.domainOverrides || {}) },
      orgid: 'org_ext_123',
      canEmailConfig: options.canEmailConfig ?? false,
    },
    global: {
      stubs: {
        RouterLink: {
          name: 'RouterLink',
          template: '<a :data-to="JSON.stringify(to)" :class="$attrs.class"><slot /></a>',
          props: ['to'],
        },
      },
    },
  });
}

describe('DomainsTableDomainCell', () => {
  beforeEach(() => {
    // Default: no warning or error (verified state)
    mockUseDomainStatus.mockReturnValue({
      isWarning: false,
      isError: false,
      displayStatus: 'Verified',
    });
    // The strategy is module state in the support helper, so re-assert the default.
    setDomainValidationStrategy('approximated');
  });

  afterEach(() => {
    vi.clearAllMocks();
    useRealDomainStatus = false;
  });

  describe('domain name link', () => {
    it('always routes the display-domain link to DomainDetail', () => {
      const wrapper = mountComponent();

      const link = wrapper.find('a[data-to]');
      const to = JSON.parse(link.attributes('data-to')!);

      expect(to.name).toBe('DomainDetail');
      expect(to.params).toEqual({
        orgid: 'org_ext_123',
        extid: 'dm-test-extid',
      });
      expect(link.text()).toBe('test.example.com');
    });
  });

  describe('DNS warning/error states (UI consistency)', () => {
    it('shows clickable warning link when isWarning is true', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      // Should show warning link
      const warningLink = wrapper.find('.text-amber-600');
      expect(warningLink.exists()).toBe(true);
      expect(warningLink.text()).toContain('DNS Check Required');
    });

    it('shows clickable warning link when isError is true', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: true,
        displayStatus: 'DNS Error',
      });

      const wrapper = mountComponent();

      // Should show error link (same amber styling)
      const errorLink = wrapper.find('.text-amber-600');
      expect(errorLink.exists()).toBe(true);
      expect(errorLink.text()).toContain('DNS Error');
    });

    it('warning link routes to verify page', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      const warningLink = wrapper.find('.text-amber-600');
      const to = warningLink.attributes('data-to');
      expect(to).toBe('"/org/org_ext_123/domains/dm-test-extid/verify"');
    });

    it('shows alert icon in warning state', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      const alertIcon = wrapper.find('[data-icon-name="alert-circle"]');
      expect(alertIcon.exists()).toBe(true);
    });

    it('hides DomainVerificationInfo when in warning/error state', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      // Should NOT show the verification info component
      const verificationInfo = wrapper.find('[data-testid="verification-info"]');
      expect(verificationInfo.exists()).toBe(false);
    });

    it('shows DomainVerificationInfo when no warning/error', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: false,
        displayStatus: 'Verified',
      });

      const wrapper = mountComponent();

      // Should show the verification info component
      const verificationInfo = wrapper.find('[data-testid="verification-info"]');
      expect(verificationInfo.exists()).toBe(true);
    });

    it('hides age timestamp when in warning/error state', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      // Should NOT show age timestamp (which uses 3 days ago from mock)
      expect(wrapper.text()).not.toContain('3 days ago');
    });

    it('shows age timestamp when no warning/error', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: false,
        displayStatus: 'Verified',
      });

      const wrapper = mountComponent();

      // Should show the i18n key for age (which contains formatDistanceToNow)
      // The actual rendered text will use i18n interpolation with the mocked date-fns
      expect(wrapper.text()).toContain('web.domains.added_formatdistancetonow_domain_created_addsuffix_true');
    });
  });

  describe.each(OWNERSHIP_CHECKING_STRATEGIES)('%s validation strategy', (strategy) => {
    beforeEach(() => {
      setDomainValidationStrategy(strategy);
    });

    it('shows the status icon when healthy', () => {
      const wrapper = mountComponent();

      expect(wrapper.find('[data-testid="verification-info"]').exists()).toBe(true);
    });

    it('links the status text to the verify page when the TXT check is outstanding', () => {
      mockUseDomainStatus.mockReturnValue({
        needsOwnershipCheck: true,
        displayStatus: 'web.domains.pending_verification',
      });

      const wrapper = mountComponent();
      const link = wrapper.find('a.text-amber-600');

      expect(link.exists()).toBe(true);
      expect(link.attributes('data-to')).toBe('"/org/org_ext_123/domains/dm-test-extid/verify"');
      expect(link.attributes('aria-label')).toBe(
        'web.domains.pending_verification. web.domains.verify_now'
      );
      expect(link.text()).toContain('web.domains.pending_verification');
    });

    // Real composable from here: the label and link come from the record.
    describe('from the domain record', () => {
      const activeBlob = { status: 'ACTIVE_SSL', last_monitored_unix: new Date('2024-01-02') };

      beforeEach(() => {
        useRealDomainStatus = true;
      });

      // After a demotion the certificate issued earlier keeps serving, so the
      // blob stays ACTIVE_SSL while verified is false.
      it('links to the verify page instead of reading active when verified is false', () => {
        const wrapper = mountComponent({ domainOverrides: { verified: false, vhost: activeBlob } });
        const link = wrapper.find('a.text-amber-600');

        expect(link.exists()).toBe(true);
        expect(link.attributes('data-to')).toBe('"/org/org_ext_123/domains/dm-test-extid/verify"');
        expect(link.text()).toContain('web.domains.pending_verification');
        expect(link.text()).not.toContain('web.STATUS.active');
        expect(link.find('[data-icon-name="alert-circle"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="verification-info"]').exists()).toBe(false);
      });

      it('keeps the status icon for the same blob when verified is true', () => {
        const wrapper = mountComponent({ domainOverrides: { verified: true, vhost: activeBlob } });

        expect(wrapper.find('a.text-amber-600').exists()).toBe(false);
        expect(wrapper.find('[data-testid="verification-info"]').exists()).toBe(true);
      });

      it('announces a failed check and an outstanding ownership check differently', () => {
        const stale = mountComponent({
          domainOverrides: {
            verified: true,
            vhost: activeBlob,
            vhost_fetch_failed_at: Date.now() / 1000 - 60,
          },
        }).find('a.text-amber-600');
        const unverified = mountComponent({
          domainOverrides: { verified: false, vhost: activeBlob },
        }).find('a.text-amber-600');

        expect(stale.attributes('aria-label')).toBe(
          'web.STATUS.unverified. web.domains.verify_now'
        );
        expect(unverified.attributes('aria-label')).toBe(
          'web.domains.pending_verification. web.domains.verify_now'
        );
        expect(stale.text()).toContain('web.STATUS.unverified');
        expect(unverified.text()).not.toContain('web.STATUS.unverified');
      });
    });

    it('keeps the status icon, not a warning link, while awaiting the first certificate', () => {
      // isAwaitingCertificate sets none of the attention flags.
      mockUseDomainStatus.mockReturnValue({ displayStatus: 'web.STATUS.pending_ssl' });

      const wrapper = mountComponent();

      expect(wrapper.find('a.text-amber-600').exists()).toBe(false);
      expect(wrapper.find('[data-testid="verification-info"]').exists()).toBe(true);
    });
  });

  describe('passthrough validation strategy', () => {
    beforeEach(() => {
      setDomainValidationStrategy('passthrough');
    });

    it('hides the DomainVerificationInfo status icon even when healthy', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: false,
        displayStatus: 'Verified',
      });

      const wrapper = mountComponent();

      expect(wrapper.find('[data-testid="verification-info"]').exists()).toBe(false);
    });

    it('hides the clickable DNS warning link even when isWarning is true', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      expect(wrapper.find('.text-amber-600').exists()).toBe(false);
    });

    it('still shows the added-ago timestamp', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: false,
        displayStatus: 'Verified',
      });

      const wrapper = mountComponent();

      expect(wrapper.text()).toContain(
        'web.domains.added_formatdistancetonow_domain_created_addsuffix_true'
      );
    });
  });

  describe('canEmailConfig', () => {
    /**
     * Find the email-config router-link by looking for an <a data-to> whose
     * parsed `to` object has name === 'DomainEmail'. The DomainDetail link
     * (display-domain) is also an <a data-to>, so we can't use a bare selector.
     */
    function findEmailConfigLink(wrapper: ReturnType<typeof mountComponent>) {
      return wrapper.findAll('a[data-to]').find((el) => {
        const raw = el.attributes('data-to');
        if (!raw) return false;
        try {
          const to = JSON.parse(raw);
          return to && typeof to === 'object' && to.name === 'DomainEmail';
        } catch {
          return false;
        }
      });
    }

    it('does not render the email-config link when canEmailConfig is false', () => {
      const wrapper = mountComponent({ canEmailConfig: false });
      expect(findEmailConfigLink(wrapper)).toBeUndefined();
    });

    it('renders envelope icon for not_configured state (email_config null)', () => {
      const wrapper = mountComponent({
        canEmailConfig: true,
        domainOverrides: { email_config: null },
      });

      const link = findEmailConfigLink(wrapper);
      expect(link).toBeDefined();
      expect(link!.find('[data-icon-name="envelope"]').exists()).toBe(true);
    });

    it('renders envelope icon for not_configured state (email_config undefined)', () => {
      // No override at all — mockDomain has no email_config key.
      const wrapper = mountComponent({ canEmailConfig: true });

      const link = findEmailConfigLink(wrapper);
      expect(link).toBeDefined();
      expect(link!.find('[data-icon-name="envelope"]').exists()).toBe(true);
    });

    it('renders check-circle icon for verified state', () => {
      const wrapper = mountComponent({
        canEmailConfig: true,
        domainOverrides: {
          email_config: { verification_status: 'verified', enabled: true },
        },
      });

      const link = findEmailConfigLink(wrapper);
      expect(link).toBeDefined();
      expect(link!.find('[data-icon-name="check-circle"]').exists()).toBe(true);
    });

    it('renders clock icon for pending state (config exists, not yet verified)', () => {
      const wrapper = mountComponent({
        canEmailConfig: true,
        domainOverrides: {
          email_config: { verification_status: 'pending', enabled: true },
        },
      });

      const link = findEmailConfigLink(wrapper);
      expect(link).toBeDefined();
      expect(link!.find('[data-icon-name="clock"]').exists()).toBe(true);
    });

    it('renders minus-circle icon for disabled state (enabled === false)', () => {
      // Disabled takes precedence over verification_status in emailState computed.
      const wrapper = mountComponent({
        canEmailConfig: true,
        domainOverrides: {
          email_config: { verification_status: 'verified', enabled: false },
        },
      });

      const link = findEmailConfigLink(wrapper);
      expect(link).toBeDefined();
      expect(link!.find('[data-icon-name="minus-circle"]').exists()).toBe(true);
    });

    it('does not render the email-config link in warning state even when canEmailConfig is true', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent({
        canEmailConfig: true,
        domainOverrides: {
          email_config: { verification_status: 'verified', enabled: true },
        },
      });

      // The v-else branch (which contains the email-config link) is skipped.
      expect(findEmailConfigLink(wrapper)).toBeUndefined();
    });

    it('does not render the email-config link in error state even when canEmailConfig is true', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: true,
        displayStatus: 'DNS Error',
      });

      const wrapper = mountComponent({
        canEmailConfig: true,
        domainOverrides: {
          email_config: { verification_status: 'verified', enabled: true },
        },
      });

      expect(findEmailConfigLink(wrapper)).toBeUndefined();
    });
  });
});
