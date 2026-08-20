// src/tests/apps/workspace/components/organizations/SecretActivityTable.spec.ts

/**
 * SecretActivityTable (#3637) — org secret-access audit trail.
 *
 * Mounts the real component + real useSecretActivity composable + real Zod
 * schema, with only the HTTP layer (useApi) mocked. That keeps the
 * error-vs-validationError split honest: the contract-mismatch state is
 * exercised by feeding a genuinely malformed payload through gracefulParse,
 * not by stubbing composable flags.
 *
 * i18n is pass-through (ADR-014): assertions match RAW keys, not English.
 */

import SecretActivityTable from '@/apps/workspace/components/organizations/SecretActivityTable.vue';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { createTestI18n } from '@tests/setup';

// ─── HTTP layer ──────────────────────────────────────────────────────────────
const mockApi = {
  get: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

// ─── Instance flags (#3990) ──────────────────────────────────────────────────
// Collection axis + retention cap, both from the bootstrap features payload.
// Defaults mirror the wire contract: collect on, cap 10,000.
const mockCollectEnabled = ref(true);
const mockMaxEvents = ref(10_000);
// Country column (#3989): default OFF (opt-in, pending counsel review).
const mockGeoCountryEnabled = ref(false);
vi.mock('@/utils/features', () => ({
  isSecretActivityCollectEnabled: () => mockCollectEnabled.value,
  getSecretActivityMaxEvents: () => mockMaxEvents.value,
  isSecretActivityGeoCountryEnabled: () => mockGeoCountryEnabled.value,
}));

// Deterministic classifier output so the error banner's detail line is
// assertable without pulling the whole error-classification module in.
vi.mock('@/schemas/errors', () => ({
  classifyError: (err: unknown) => ({
    message: err instanceof Error ? err.message : 'Unknown error',
  }),
}));

// ─── Presentation helpers ────────────────────────────────────────────────────
// Mock date-fns to avoid locale issues (same pattern as DomainsTableDomainCell).
// The component uses formatDistance(at, now) — NOT formatDistanceToNow — so the
// reactive clock is a real dependency of the decorated-rows computed.
vi.mock('date-fns', () => ({
  formatDistance: () => '3 minutes ago',
}));

vi.mock('@/utils/format', () => ({
  formatDisplayDateTime: (d: Date) => `DT:${d.toISOString()}`,
}));

// ─── Child components ────────────────────────────────────────────────────────
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class'],
  },
}));
vi.mock('@/shared/components/closet/TableSkeleton.vue', () => ({
  default: {
    name: 'TableSkeleton',
    template: '<div class="table-skeleton" data-testid="table-skeleton" />',
  },
}));
vi.mock('@/shared/components/ui/EmptyState.vue', () => ({
  default: {
    name: 'EmptyState',
    template: `<div class="empty-state" :data-testid="testid">
      <slot name="title" />
      <slot name="description" />
    </div>`,
    props: ['actionRoute', 'actionText', 'showAction', 'testid'],
  },
}));

// ─── Fixtures ────────────────────────────────────────────────────────────────
// Unix seconds (the wire format — transforms.fromNumber.toDate multiplies by
// 1000), chosen so the expected ISO string is a stable constant below.
const AT_UNIX_SECONDS = 1754049600; // 2025-08-01T12:00:00.000Z
const AT_ISO = new Date(AT_UNIX_SECONDS * 1000).toISOString();

// Full customer objid (the wire format for actor_id since #3637 — NIST
// AU-3(f) unique identity). Legacy events may still carry 8-char values.
const FULL_ACTOR_OBJID = '0198c0ffee15deadbeef4b1dfacade42';

interface EventOverrides {
  [key: string]: unknown;
}

const buildEvent = (overrides: EventOverrides = {}) => ({
  kind: 'burned',
  at: AT_UNIX_SECONDS,
  nonce: 'nonce-1',
  secret: 'abcd1234',
  receipt: 'rcpt5678',
  actor: 'creator',
  actor_id: 'ac12cd34',
  ...overrides,
});

interface ResponseOverrides {
  records?: object[];
  total?: number;
  offset?: number;
  limit?: number;
  /** Read-time resolution map (details.actors); omitted = older backend. */
  actors?: Record<string, { email: string; extid: string }>;
}

const buildResponse = ({
  records = [buildEvent()],
  total = records.length,
  offset = 0,
  limit = 50,
  actors,
}: ResponseOverrides = {}) => ({
  user_id: 'usr_123',
  organization_id: 'org_123',
  records,
  count: records.length,
  total,
  details: { offset, limit, ...(actors ? { actors } : {}) },
});

const respondWith = (response: object) => {
  mockApi.get.mockResolvedValue({ data: response });
};

// i18n setup (pass-through: keys render as-is, see ADR-014)
const i18n = createTestI18n();

const mountComponent = async (orgExtid = 'on1abc123') => {
  const wrapper = mount(SecretActivityTable, {
    props: { orgExtid },
    global: {
      plugins: [i18n],
    },
  });
  await flushPromises();
  return wrapper;
};

describe('SecretActivityTable', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    mockCollectEnabled.value = true;
    mockMaxEvents.value = 10_000;
    // Shipped default (#3989): country column opt-in, off until counsel signs off.
    mockGeoCountryEnabled.value = false;
    // Default: one burned event on page 1.
    respondWith(buildResponse());
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  describe('fetching', () => {
    it('fetches page 1 for its org on mount (mounting IS activation)', async () => {
      wrapper = await mountComponent('on1abc123');

      expect(mockApi.get).toHaveBeenCalledTimes(1);
      expect(mockApi.get).toHaveBeenCalledWith(
        '/api/organizations/on1abc123/secret-activity',
        expect.objectContaining({
          params: { offset: 0, limit: 50 },
        })
      );
    });
  });

  describe('unmount', () => {
    it('aborts the in-flight request on unmount', async () => {
      // Never-resolving request stays in flight until unmount.
      mockApi.get.mockReturnValue(new Promise(() => {}));

      const localWrapper = await mountComponent();
      const { signal } = mockApi.get.mock.calls[0][1] as { signal: AbortSignal };
      expect(signal.aborted).toBe(false);

      localWrapper.unmount();

      expect(signal.aborted).toBe(true);
    });
  });

  describe('loading state', () => {
    it('renders the table skeleton while the request is in flight', async () => {
      // Never-resolving request keeps isLoading pinned true.
      mockApi.get.mockReturnValue(new Promise(() => {}));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="table-skeleton"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="org-audit-table"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="org-audit-empty"]').exists()).toBe(false);
    });
  });

  describe('empty state', () => {
    it('renders the empty state for a valid zero-event response', async () => {
      respondWith(buildResponse({ records: [], total: 0 }));

      wrapper = await mountComponent();

      const empty = wrapper.find('[data-testid="org-audit-empty"]');
      expect(empty.exists()).toBe(true);
      expect(empty.text()).toContain('web.organizations.audit.empty_title');
      expect(empty.text()).toContain('web.organizations.audit.empty_description');
      expect(wrapper.find('[data-testid="org-audit-table"]').exists()).toBe(false);
    });
  });

  describe('network/HTTP error state', () => {
    it('renders the error banner with the classified message', async () => {
      mockApi.get.mockRejectedValue(new Error('Network down'));

      wrapper = await mountComponent();

      const banner = wrapper.find('[data-testid="org-audit-error"]');
      expect(banner.exists()).toBe(true);
      expect(banner.text()).toContain('web.organizations.audit.load_error');
      expect(banner.text()).toContain('Network down');
      // An error must not fall through to the empty state.
      expect(wrapper.find('[data-testid="org-audit-empty"]').exists()).toBe(false);
    });

    it('retry button refetches and recovers to the table', async () => {
      mockApi.get.mockRejectedValueOnce(new Error('Network down'));

      wrapper = await mountComponent();
      expect(wrapper.find('[data-testid="org-audit-error"]').exists()).toBe(true);

      // Second attempt succeeds (beforeEach default mockResolvedValue applies).
      const retry = wrapper.find('[data-testid="org-audit-error"] button');
      await retry.trigger('click');
      await flushPromises();

      expect(mockApi.get).toHaveBeenCalledTimes(2);
      expect(wrapper.find('[data-testid="org-audit-error"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="org-audit-table"]').exists()).toBe(true);
    });
  });

  describe('contract-mismatch (validation error) state', () => {
    beforeEach(() => {
      // gracefulParse console.errors schema failures in test env; keep output quiet.
      vi.spyOn(console, 'error').mockImplementation(() => {});
    });

    it('renders the dedicated mismatch state, never the empty state', async () => {
      // Envelope missing `details` → fails secretActivityResponseSchema.
      respondWith({
        user_id: 'usr_123',
        organization_id: 'org_123',
        records: [],
        count: 0,
        total: 0,
      });

      wrapper = await mountComponent();

      const mismatch = wrapper.find('[data-testid="org-audit-contract-mismatch"]');
      expect(mismatch.exists()).toBe(true);
      expect(mismatch.text()).toContain('web.organizations.audit.contract_mismatch');
      // The worst possible lie on an audit log: a parse failure rendering as
      // "no activity yet". Assert it cannot happen.
      expect(wrapper.find('[data-testid="org-audit-empty"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="org-audit-table"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="org-audit-error"]').exists()).toBe(false);
    });

    it('treats a malformed record (non-numeric at) as a mismatch, not empty', async () => {
      respondWith(buildResponse({ records: [buildEvent({ at: 'yesterday' })] }));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-contract-mismatch"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="org-audit-empty"]').exists()).toBe(false);
    });

    it('mismatch retry button refetches', async () => {
      respondWith(buildResponse({ records: [buildEvent({ at: 'yesterday' })] }));

      wrapper = await mountComponent();

      const retry = wrapper.find('[data-testid="org-audit-contract-mismatch"] button');
      expect(retry.exists()).toBe(true);
      await retry.trigger('click');
      await flushPromises();

      expect(mockApi.get).toHaveBeenCalledTimes(2);
    });
  });

  describe('org switch', () => {
    // The orgExtid watcher must reset the FULL previous-org context — not
    // just records. A latched error/validationError would otherwise suppress
    // the skeleton (its gate requires both clear) and render the old org's
    // failure banner over the new org's first fetch.

    it('clears a latched error on switch so the skeleton renders for the new org', async () => {
      mockApi.get.mockRejectedValueOnce(new Error('Network down'));
      wrapper = await mountComponent('on1abc123');
      expect(wrapper.find('[data-testid="org-audit-error"]').exists()).toBe(true);

      // The new org's first fetch stays in flight.
      mockApi.get.mockReturnValue(new Promise(() => {}));
      await wrapper.setProps({ orgExtid: 'on1def456' });
      await flushPromises();

      expect(mockApi.get).toHaveBeenLastCalledWith(
        '/api/organizations/on1def456/secret-activity',
        expect.objectContaining({ params: { offset: 0, limit: 50 } })
      );
      expect(wrapper.find('[data-testid="org-audit-error"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="table-skeleton"]').exists()).toBe(true);
    });

    it('clears a latched contract mismatch on switch so the skeleton renders', async () => {
      vi.spyOn(console, 'error').mockImplementation(() => {});
      respondWith(buildResponse({ records: [buildEvent({ at: 'yesterday' })] }));
      wrapper = await mountComponent('on1abc123');
      expect(wrapper.find('[data-testid="org-audit-contract-mismatch"]').exists()).toBe(true);

      mockApi.get.mockReturnValue(new Promise(() => {}));
      await wrapper.setProps({ orgExtid: 'on1def456' });
      await flushPromises();

      expect(wrapper.find('[data-testid="org-audit-contract-mismatch"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="table-skeleton"]').exists()).toBe(true);
    });

    it('drops the previous org resolved-identity map across the switch', async () => {
      respondWith(
        buildResponse({
          records: [buildEvent({ actor: 'creator', actor_id: FULL_ACTOR_OBJID })],
          actors: {
            [FULL_ACTOR_OBJID]: { email: 'alice@example.com', extid: 'cx1abc123' },
          },
        })
      );
      wrapper = await mountComponent('on1abc123');
      expect(wrapper.text()).toContain('alice@example.com');

      mockApi.get.mockReturnValue(new Promise(() => {}));
      await wrapper.setProps({ orgExtid: 'on1def456' });
      await flushPromises();

      // Rows are cleared on switch, so a stale map cannot render today —
      // assert the setup state directly (defense-in-depth): the map must be
      // empty while the new org's first fetch is in flight, not still holding
      // org A's identities.
      const vm = wrapper.vm as unknown as { actors: Record<string, unknown> };
      expect(vm.actors).toEqual({});
    });

    it('retry after a failed first fetch of the new org requests page 1, not the stale offset', async () => {
      // Paginate org A to offset 50 (server-echoed on the next-page response).
      respondWith(buildResponse({ records: [buildEvent()], total: 120, offset: 0 }));
      wrapper = await mountComponent('on1abc123');
      respondWith(buildResponse({ records: [buildEvent()], total: 120, offset: 50 }));
      await wrapper.find('[data-testid="org-audit-next"]').trigger('click');
      await flushPromises();

      // Org B's first fetch fails → Retry replays fetchPage(offset.value).
      // With a stale offset the retry would land mid-trail in org B.
      mockApi.get.mockRejectedValueOnce(new Error('Network down'));
      await wrapper.setProps({ orgExtid: 'on1def456' });
      await flushPromises();
      expect(wrapper.find('[data-testid="org-audit-error"]').exists()).toBe(true);

      await wrapper.find('[data-testid="org-audit-error"] button').trigger('click');
      await flushPromises();

      expect(mockApi.get).toHaveBeenLastCalledWith(
        '/api/organizations/on1def456/secret-activity',
        expect.objectContaining({ params: { offset: 0, limit: 50 } })
      );
    });
  });

  describe('kind labels and icons', () => {
    it('resolves a known kind to its i18n label key and dedicated icon', async () => {
      respondWith(buildResponse({ records: [buildEvent({ kind: 'burned' })] }));

      wrapper = await mountComponent();

      const row = wrapper.find('[data-testid="org-audit-row"]');
      expect(row.text()).toContain('web.organizations.audit.kinds.burned');
      expect(row.find('[data-icon-name="fire"]').exists()).toBe(true);
    });

    it('resolves each shipped kind to a namespaced label key', async () => {
      const kinds = [
        'created',
        'status_get',
        'secret_get',
        'previewed',
        'creator_status_get',
        'receipt_viewed',
        'revealed',
        'burned',
        'expired',
        'orphaned',
        'reveal_failed_undecryptable',
      ];
      respondWith(
        buildResponse({
          records: kinds.map((kind, i) => buildEvent({ kind, nonce: `nonce-${i}` })),
        })
      );

      wrapper = await mountComponent();

      const rows = wrapper.findAll('[data-testid="org-audit-row"]');
      expect(rows).toHaveLength(kinds.length);
      kinds.forEach((kind, i) => {
        expect(rows[i].text()).toContain(`web.organizations.audit.kinds.${kind}`);
      });
    });

    it('falls back to the raw kind name and info icon for an unknown future kind', async () => {
      respondWith(buildResponse({ records: [buildEvent({ kind: 'quantum_leak' })] }));

      wrapper = await mountComponent();

      // Unknown kind must pass schema validation (kind is z.string()) and
      // render its raw name — not an i18n key, and not the mismatch state.
      expect(wrapper.find('[data-testid="org-audit-contract-mismatch"]').exists()).toBe(false);
      const row = wrapper.find('[data-testid="org-audit-row"]');
      expect(row.exists()).toBe(true);
      expect(row.text()).toContain('quantum_leak');
      expect(row.text()).not.toContain('web.organizations.audit.kinds.quantum_leak');
      expect(row.find('[data-icon-name="information-circle"]').exists()).toBe(true);
    });
  });

  describe('timestamps', () => {
    it('renders a <time> element with the ISO datetime attribute', async () => {
      wrapper = await mountComponent();

      const time = wrapper.find('[data-testid="org-audit-row"] time');
      expect(time.exists()).toBe(true);
      expect(time.attributes('datetime')).toBe(AT_ISO);
      expect(time.text()).toBe(`DT:${AT_ISO}`);
    });

    it('renders the relative time from date-fns formatDistance', async () => {
      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-row"]').text()).toContain('3 minutes ago');
    });
  });

  describe('actor column', () => {
    it('renders the resolved email when details.actors resolves the full objid', async () => {
      respondWith(
        buildResponse({
          records: [buildEvent({ actor: 'creator', actor_id: FULL_ACTOR_OBJID })],
          actors: {
            [FULL_ACTOR_OBJID]: { email: 'alice@example.com', extid: 'cx1abc123' },
          },
        })
      );

      wrapper = await mountComponent();

      const row = wrapper.find('[data-testid="org-audit-row"]');
      expect(row.text()).toContain('web.organizations.audit.actors.creator');
      expect(row.text()).toContain('alice@example.com');
      // The raw objid never renders when resolved — email is the identity.
      expect(row.text()).not.toContain(FULL_ACTOR_OBJID);
      // title carries the full value in case the chip truncates visually.
      const chip = row.find('[title="alice@example.com"]');
      expect(chip.exists()).toBe(true);
    });

    it('renders the bare objid when the actor is unresolved (removed member)', async () => {
      // CloudTrail deleted-principal semantics: absent map key = unresolved
      // but still unique — the full objid IS the identity on record.
      respondWith(
        buildResponse({
          records: [buildEvent({ actor: 'authenticated_other', actor_id: FULL_ACTOR_OBJID })],
          actors: {},
        })
      );

      wrapper = await mountComponent();

      const row = wrapper.find('[data-testid="org-audit-row"]');
      expect(row.text()).toContain(FULL_ACTOR_OBJID);
      expect(row.find(`[title="${FULL_ACTOR_OBJID}"]`).exists()).toBe(true);
    });

    it('renders a legacy 8-char actor_id as-is when no actors map is present', async () => {
      // Older backend response: no details.actors at all, historical shortid.
      respondWith(
        buildResponse({
          records: [buildEvent({ actor: 'creator', actor_id: 'ac12cd34' })],
        })
      );

      wrapper = await mountComponent();

      const row = wrapper.find('[data-testid="org-audit-row"]');
      expect(row.text()).toContain('web.organizations.audit.actors.creator');
      expect(row.text()).toContain('ac12cd34');
    });

    it("renders the system label without an id chip for actor 'system'", async () => {
      respondWith(
        buildResponse({
          records: [buildEvent({ kind: 'expired', actor: 'system', actor_id: undefined })],
        })
      );

      wrapper = await mountComponent();

      const row = wrapper.find('[data-testid="org-audit-row"]');
      expect(row.text()).toContain('web.organizations.audit.actors.system');
      expect(row.find('td:nth-child(3) .font-mono').exists()).toBe(false);
    });

    it("renders the explicit Unknown label with the id chip for actor 'unknown' (ADR-023)", async () => {
      // The ADR-023 sentinel: an authenticated principal acted but their
      // relationship to the secret could not be established. It is
      // id-carrying, so the identity chip renders like any authenticated
      // actor — never a blank or a misleading label.
      respondWith(
        buildResponse({
          records: [buildEvent({ actor: 'unknown', actor_id: FULL_ACTOR_OBJID })],
          actors: {
            [FULL_ACTOR_OBJID]: { email: 'alice@example.com', extid: 'cx1abc123' },
          },
        })
      );

      wrapper = await mountComponent();

      const row = wrapper.find('[data-testid="org-audit-row"]');
      expect(row.text()).toContain('web.organizations.audit.actors.unknown');
      expect(row.text()).toContain('alice@example.com');
    });

    it('shows a placeholder dash when the event has no actor', async () => {
      respondWith(
        buildResponse({
          records: [buildEvent({ kind: 'expired', actor: undefined, actor_id: undefined })],
        })
      );

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-row"]').text()).toContain('—');
    });
  });

  describe('retention cap notice', () => {
    it('shows the capped notice when total saturates at 10,000', async () => {
      respondWith(buildResponse({ records: [buildEvent()], total: 10_000 }));

      wrapper = await mountComponent();

      const notice = wrapper.find('[data-testid="org-audit-capped"]');
      expect(notice.exists()).toBe(true);
      expect(notice.text()).toContain('web.organizations.audit.capped_notice');
    });

    it('hides the capped notice below the retention cap', async () => {
      respondWith(buildResponse({ records: [buildEvent()], total: 9_999 }));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-capped"]').exists()).toBe(false);
    });

    it('honors a non-default operator-configured cap (#3990)', async () => {
      mockMaxEvents.value = 500;
      respondWith(buildResponse({ records: [buildEvent()], total: 500 }));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-capped"]').exists()).toBe(true);
    });

    it('does not treat 10,000 as capped when the configured cap is higher', async () => {
      mockMaxEvents.value = 50_000;
      respondWith(buildResponse({ records: [buildEvent()], total: 10_000 }));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-capped"]').exists()).toBe(false);
    });

    /**
     * The notice states a retention number, so it must state the CONFIGURED
     * one — the pre-#3990 string hardcoded "10,000" and lied on every instance
     * running a different cap. Mounted against the REAL generated bundle (not
     * the pass-through i18n, and not hand-typed copy) so the assertion tests
     * the wiring: drop the `{ max }` argument and vue-i18n renders a silent
     * double-space sentence rather than a visible `{max}`, which only the
     * shipped string can catch.
     *
     * The cap is 10,000 rather than a small number so the thousands separator
     * from toLocaleString() is part of the contract under test.
     */
    it('interpolates the configured cap into the capped notice (#3990)', async () => {
      const realEn = JSON.parse(
        readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')
      );
      const realI18n = createI18n({ legacy: false, locale: 'en', messages: { en: realEn } });

      mockMaxEvents.value = 10_000;
      respondWith(buildResponse({ records: [buildEvent()], total: 10_000 }));

      wrapper = mount(SecretActivityTable, {
        props: { orgExtid: 'on1abc123' },
        global: { plugins: [realI18n] },
      });
      await flushPromises();

      const text = wrapper.find('[data-testid="org-audit-capped"]').text();
      // Locale-independent: whatever separator the runtime picks, the notice
      // must carry the formatted cap the helper produced.
      expect(text).toContain((10_000).toLocaleString());
      expect(text).not.toContain('{max}');
    });
  });

  describe('collection-paused notice (#3990)', () => {
    it('renders the paused banner above a populated trail when collection is off', async () => {
      mockCollectEnabled.value = false;

      wrapper = await mountComponent();

      const notice = wrapper.find('[data-testid="org-audit-paused"]');
      expect(notice.exists()).toBe(true);
      expect(notice.text()).toContain('web.organizations.audit.collection_paused_notice');
      // Historical events keep rendering — the banner warns the trail is
      // frozen, it does not hide it.
      expect(wrapper.find('[data-testid="org-audit-table"]').exists()).toBe(true);
    });

    it('renders the paused banner alongside the empty state (frozen ≠ no activity yet)', async () => {
      mockCollectEnabled.value = false;
      respondWith(buildResponse({ records: [], total: 0 }));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-paused"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="org-audit-empty"]').exists()).toBe(true);
    });

    it('hides the paused banner when collection is on', async () => {
      mockCollectEnabled.value = true;

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-paused"]').exists()).toBe(false);
    });
  });

  describe('country column gate (#3989)', () => {
    // The country field is legally-sensitive org-tier geo data pending counsel
    // review (ADR-021), so the FRONTEND gates its display: the field may be
    // present on the wire and still must not render. The gate is read once at
    // setup, so every case below sets the flag BEFORE mounting.
    const COUNTRY_HEADER_KEY = 'web.organizations.audit.columns.country';
    const COUNTRY_UNKNOWN_KEY = 'web.organizations.audit.country_unknown';

    const headerCells = (w: VueWrapper) =>
      w.findAll('[data-testid="org-audit-table"] thead th');
    const rowCells = (w: VueWrapper) =>
      w
        .findAll('[data-testid="org-audit-row"]')
        .map((row) => row.findAll('td'));

    it('renders neither the country header nor any country cell when the flag is off', async () => {
      // net_country present on the wire — the gate, not the payload, decides.
      respondWith(buildResponse({ records: [buildEvent({ net_country: 'US' })] }));

      wrapper = await mountComponent();

      const headers = headerCells(wrapper);
      expect(headers.map((th) => th.text())).not.toContain(COUNTRY_HEADER_KEY);
      const row = wrapper.find('[data-testid="org-audit-row"]');
      expect(row.exists()).toBe(true);
      // Neither the value nor the fallback leaks into the rendered row.
      expect(row.text()).not.toContain('US');
      expect(row.text()).not.toContain(COUNTRY_UNKNOWN_KEY);
    });

    it('renders the country header and the row value when the flag is on', async () => {
      mockGeoCountryEnabled.value = true;
      respondWith(buildResponse({ records: [buildEvent({ net_country: 'US' })] }));

      wrapper = await mountComponent();

      expect(headerCells(wrapper).map((th) => th.text())).toContain(COUNTRY_HEADER_KEY);
      // Column 4 (Event, Secret, Actor, Country, When) carries the code itself.
      expect(rowCells(wrapper)[0][3].text()).toBe('US');
    });

    it('falls back to the country_unknown label when the row carries no net_country', async () => {
      mockGeoCountryEnabled.value = true;
      respondWith(buildResponse({ records: [buildEvent({ net_country: undefined })] }));

      wrapper = await mountComponent();

      const cell = rowCells(wrapper)[0][3];
      // An audit cell must never render "undefined" or read as blank — the
      // absence of geo data is itself a stated fact.
      expect(cell.text()).toBe(COUNTRY_UNKNOWN_KEY);
      expect(cell.text()).not.toContain('undefined');
      expect(cell.text()).not.toBe('');
    });

    /**
     * The `v-if="showCountry"` is DUPLICATED on the <th> and the <td>. If a
     * future edit drops one side, the table still renders — every column's
     * data just silently shifts one cell out of alignment, which on an audit
     * trail means attributing an event to the wrong timestamp/actor. Header
     * count and per-row cell count must therefore agree in BOTH flag states.
     */
    it('keeps header count and per-row cell count in agreement in both flag states (misaligned columns would silently shift every column by one)', async () => {
      const countsFor = async (enabled: boolean) => {
        mockGeoCountryEnabled.value = enabled;
        respondWith(
          buildResponse({
            records: [
              buildEvent({ nonce: 'nonce-1', net_country: 'US' }),
              // Second row omits net_country: the fallback must still occupy a
              // cell, so a missing value can never collapse the row's width.
              buildEvent({ nonce: 'nonce-2', net_country: undefined }),
            ],
          })
        );

        const localWrapper = await mountComponent();
        const headers = headerCells(localWrapper).length;
        const cells = rowCells(localWrapper).map((tds) => tds.length);
        localWrapper.unmount();
        return { headers, cells };
      };

      const off = await countsFor(false);
      expect(off.headers).toBe(4);
      expect(off.cells).toEqual([4, 4]);

      const on = await countsFor(true);
      expect(on.headers).toBe(5);
      expect(on.cells).toEqual([5, 5]);

      // The gate adds exactly one column, on both sides of the table.
      expect(on.headers - off.headers).toBe(1);
    });
  });

  describe('pagination', () => {
    const twoEvents = () => [
      buildEvent({ nonce: 'nonce-1' }),
      buildEvent({ nonce: 'nonce-2' }),
    ];

    it('disables prev on the first page and enables next when more exist', async () => {
      respondWith(buildResponse({ records: twoEvents(), total: 120, offset: 0 }));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-prev"]').attributes('disabled')).toBeDefined();
      expect(
        wrapper.find('[data-testid="org-audit-next"]').attributes('disabled')
      ).toBeUndefined();
    });

    it('disables next on the last page and enables prev', async () => {
      // offset 100 + count 2 = 102 = total → no next page.
      respondWith(buildResponse({ records: twoEvents(), total: 102, offset: 100 }));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-next"]').attributes('disabled')).toBeDefined();
      expect(
        wrapper.find('[data-testid="org-audit-prev"]').attributes('disabled')
      ).toBeUndefined();
    });

    it('disables both buttons when the only page is also the last', async () => {
      respondWith(buildResponse({ records: twoEvents(), total: 2, offset: 0 }));

      wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="org-audit-prev"]').attributes('disabled')).toBeDefined();
      expect(wrapper.find('[data-testid="org-audit-next"]').attributes('disabled')).toBeDefined();
    });

    it('next requests the following page using the server-echoed limit', async () => {
      respondWith(buildResponse({ records: twoEvents(), total: 120, offset: 0, limit: 50 }));

      wrapper = await mountComponent();
      await wrapper.find('[data-testid="org-audit-next"]').trigger('click');
      await flushPromises();

      expect(mockApi.get).toHaveBeenLastCalledWith(
        '/api/organizations/on1abc123/secret-activity',
        expect.objectContaining({
          params: { offset: 50, limit: 50 },
        })
      );
    });
  });

  describe('accessibility', () => {
    it('puts role=log + aria-live=polite on a wrapper, keeping the table native', async () => {
      wrapper = await mountComponent();

      const log = wrapper.find('[role="log"]');
      expect(log.exists()).toBe(true);
      expect(log.attributes('aria-live')).toBe('polite');
      expect(log.attributes('aria-label')).toBe('web.organizations.audit.title');
      // The log wrapper is NOT the table element — native table semantics
      // (cell navigation) must survive.
      expect(log.element.tagName).not.toBe('TABLE');
      const table = log.find('table[data-testid="org-audit-table"]');
      expect(table.exists()).toBe(true);
      expect(table.attributes('role')).toBeUndefined();
      expect(table.attributes('aria-live')).toBeUndefined();
    });
  });
});
