// src/tests/apps/workspace/components/domains/DomainVerificationInfo.spec.ts

import DomainVerificationInfo from '@/apps/workspace/components/domains/DomainVerificationInfo.vue';
import { vhostSchema } from '@/schemas/shapes/v3/custom-domain/vhost';
import { createTestI18n } from '@tests/setup';
import { mount, RouterLinkStub } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name'],
  },
}));

// i18n pass-through: keys render as-is (ADR-014).
const i18n = createTestI18n();

const MONITORED = new Date(1700000000000);

const createDomain = (overrides: Record<string, unknown> = {}) => ({
  extid: 'dm-test-extid',
  display_domain: 'test.example.com',
  verified: true,
  vhost_fetch_failed_at: null,
  vhost: { status: 'ACTIVE_SSL', has_ssl: true, last_monitored_unix: MONITORED },
  ...overrides,
});

const mountInfo = (domain: Record<string, unknown>, mode = 'table') =>
  mount(DomainVerificationInfo, {
    props: { domain, mode, orgid: 'org_ext_123' } as never,
    global: { plugins: [i18n], stubs: { RouterLink: RouterLinkStub } },
  });

describe('DomainVerificationInfo', () => {
  // vhost.has_ssl is three-valued on the wire: true, false, or absent when
  // the check could not tell. The caddy_on_demand probe omits it when port 443
  // was unreachable or the stored certificate dates have lapsed.
  describe('SSL status row', () => {
    const sslRow = (vhost: Record<string, unknown>) =>
      mountInfo(createDomain({ vhost: { last_monitored_unix: MONITORED, ...vhost } })).find(
        '[data-testid="vhost-ssl-status"]'
      );

    it('reads active for has_ssl: true', () => {
      const row = sslRow({ status: 'ACTIVE_SSL', has_ssl: true });

      expect(row.text()).toBe('web.COMMON.active');
      expect(row.classes()).toContain('text-emerald-600');
    });

    it('reads inactive for a definite has_ssl: false', () => {
      const row = sslRow({ status: 'PENDING_SSL', has_ssl: false });

      expect(row.text()).toBe('web.COMMON.inactive');
      expect(row.classes()).toContain('text-rose-600');
    });

    it('reads unknown, not inactive, when has_ssl is absent', () => {
      const row = sslRow({ status: 'PENDING_SSL' });

      expect(row.text()).toBe('web.COMMON.unknown');
      expect(row.classes()).not.toContain('text-rose-600');
      expect(row.classes()).toContain('text-gray-500');
    });
  });

  // The table serves both payload shapes. Approximated's carries
  // target_address and last_monitored_humanized; the caddy_on_demand probe
  // (source: 'tls_probe') writes neither, only last_monitored_unix in epoch
  // seconds, which the v3 vhost schema parses to a Date.
  describe('payload-specific rows', () => {
    const targetRow = '[data-testid="vhost-target-address"]';
    const lastMonitored = '[data-testid="vhost-last-monitored"]';

    const probeBlob = () =>
      vhostSchema.parse({
        incoming_address: 'test.example.com',
        status: 'ACTIVE_SSL',
        status_message: 'Resolves to this install',
        is_resolving: true,
        dns_pointed_at: '203.0.113.10',
        has_ssl: true,
        last_monitored_unix: Math.floor(Date.now() / 1000) - 3600,
        source: 'tls_probe',
      });

    it('probe-shaped blob: last monitored is derived from last_monitored_unix', () => {
      const wrapper = mountInfo(createDomain({ vhost: probeBlob() }));

      expect(wrapper.find(lastMonitored).text()).toBe('about 1 hour ago');
    });

    it('probe-shaped blob: the target address row is not rendered', () => {
      const wrapper = mountInfo(createDomain({ vhost: probeBlob() }));

      expect(wrapper.find(targetRow).exists()).toBe(false);
      expect(wrapper.text()).not.toContain('web.domains.target_address');
    });

    it('Approximated-shaped blob: both rows render from the payload', () => {
      const wrapper = mountInfo(
        createDomain({
          vhost: {
            status: 'ACTIVE_SSL',
            has_ssl: true,
            target_address: 'proxy.example.net',
            last_monitored_unix: MONITORED,
            last_monitored_humanized: '5 minutes ago',
          },
        })
      );

      expect(wrapper.find(targetRow).text()).toContain('proxy.example.net');
      expect(wrapper.find(lastMonitored).text()).toBe('5 minutes ago');
    });

    it('an unusable last_monitored_unix renders an empty value rather than throwing', () => {
      const wrapper = mountInfo(
        createDomain({ vhost: { status: 'ACTIVE_SSL', last_monitored_unix: new Date(NaN) } })
      );

      expect(wrapper.find(lastMonitored).text()).toBe('');
    });
  });

  describe('icon mode', () => {
    const icon = (domain: Record<string, unknown>) => {
      const wrapper = mountInfo(domain, 'icon');
      const link = wrapper.findComponent(RouterLinkStub);
      return {
        to: link.props('to'),
        tooltip: link.attributes('data-tooltip'),
        name: wrapper.find('.o-icon').attributes('data-name'),
        classes: wrapper.find('.o-icon').classes(),
      };
    };

    it('links to the org-qualified verify route', () => {
      expect(icon(createDomain()).to).toBe('/org/org_ext_123/domains/dm-test-extid/verify');
    });

    it('active domain', () => {
      const result = icon(createDomain());

      expect(result.name).toBe('check-circle');
      expect(result.tooltip).toBe('web.domains.status_tooltip_active');
      expect(result.classes).toContain('text-emerald-600');
    });

    it('verified domain awaiting its first certificate is not shown as an error', () => {
      const result = icon(
        createDomain({
          verified: true,
          vhost: { status: 'PENDING_SSL', last_monitored_unix: MONITORED },
        })
      );

      expect(result.name).toBe('timer-outline');
      expect(result.tooltip).toBe('web.domains.status_tooltip_pending_ssl');
      expect(result.classes).toContain('text-sky-600');
      expect(result.classes).not.toContain('text-rose-600');
    });

    it('resolving domain whose TXT check has not passed asks for verification', () => {
      const result = icon(
        createDomain({
          verified: false,
          vhost: { status: 'PENDING_SSL', last_monitored_unix: MONITORED },
        })
      );

      expect(result.name).toBe('alert-circle');
      expect(result.tooltip).toBe('web.domains.status_tooltip_not_verified');
      expect(result.classes).toContain('text-amber-500');
    });

    it('status blob still reads active but the TXT check no longer passes', () => {
      const result = icon(
        createDomain({
          verified: false,
          vhost: { status: 'ACTIVE_SSL', has_ssl: true, last_monitored_unix: MONITORED },
        })
      );

      expect(result.name).not.toBe('check-circle');
      expect(result.tooltip).toBe('web.domains.status_tooltip_not_verified');
      expect(result.classes).not.toContain('text-emerald-600');
    });

    it('DNS_INCORRECT', () => {
      const result = icon(createDomain({ vhost: { status: 'DNS_INCORRECT' } }));

      expect(result.name).toBe('alert-circle');
      expect(result.tooltip).toBe('web.domains.status_tooltip_dns_incorrect');
    });

    it('no status yet', () => {
      const result = icon(createDomain({ verified: false, vhost: {} }));

      expect(result.name).toBe('close-circle');
      expect(result.tooltip).toBe('web.domains.status_tooltip_not_verified');
      expect(result.classes).toContain('text-rose-600');
    });
  });
});
