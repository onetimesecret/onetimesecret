// src/tests/apps/admin/useAdminDomains.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  put: vi.fn(),
  delete: vi.fn(),
};

vi.mock('@/shared/composables/useApi', () => ({
  useApi: () => mockApi,
}));

import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';

function domainRow(overrides: Record<string, unknown> = {}) {
  return {
    domain_id: 'cd1',
    extid: 'cd_abc123',
    display_domain: 'secrets.example.com',
    base_domain: 'example.com',
    subdomain: 'secrets',
    status: null,
    verified: true,
    resolving: true,
    verification_state: 'verified',
    ready: true,
    created: 1700000000,
    updated: 1700003600,
    org_id: 'org1',
    org_name: 'Acme',
    brand: { name: 'Acme', tagline: null, homepage_url: null },
    homepage_config: null,
    api_config: null,
    has_logo: false,
    has_icon: false,
    logo_url: null,
    icon_url: null,
    ...overrides,
  };
}

function domainsPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      domains: [domainRow()],
      pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
    },
  };
}

describe('useAdminDomains', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id', () => {
    expect(useAdminDomains().$id).toBe('adminDomains');
  });

  it('fetches the domains endpoint and maps the page via its own selector', async () => {
    mockApi.get.mockResolvedValue({ data: domainsPayload() });
    const store = useAdminDomains();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/domains', {
      params: { page: 1, per_page: 50 },
    });
    expect(store.domains).toHaveLength(1);
    expect(store.domains[0].display_domain).toBe('secrets.example.com');
    expect(store.domains[0].created).toBeInstanceOf(Date);
    expect(store.pagination?.total_count).toBe(1);
  });

  it('clears rows and rethrows on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    const store = useAdminDomains();

    await expect(store.fetchPage(1)).rejects.toThrow('Network Error');
    expect(store.domains).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.error).toBeInstanceOf(Error);
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: domainsPayload() });
    const store = useAdminDomains();
    await store.fetchPage(1);
    expect(store.domains).toHaveLength(1);

    store.$reset();

    expect(store.domains).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
  });

  describe('per-domain config operations', () => {
    const EXTID = 'cd_abc123';
    const CONFIGS_URL = `/api/colonel/domains/${EXTID}/configs`;

    const envelopeRecord = () => ({
      domain_id: 'cd1',
      extid: EXTID,
      display_domain: 'secrets.example.com',
    });

    const signinConfig = () => ({
      domain_id: 'cd1',
      enabled: true,
      signin_enabled: true,
      email_auth_enabled: false,
      sso_enabled: false,
      restrict_to: null,
      created: 1700000000,
      updated: 1700003600,
    });

    function configsPayload() {
      return {
        shrimp: '',
        record: envelopeRecord(),
        details: {
          configs: {
            signin: { exists: true, config: signinConfig() },
            signup: { exists: false, config: null },
            homepage: { exists: false, config: null },
            api: { exists: false, config: null },
            incoming: { exists: false, config: null },
            sso: { exists: false, config: null },
            mailer: { exists: false, config: null },
          },
        },
      };
    }

    it('fetchConfigs GETs the configs subresource and returns the details', async () => {
      mockApi.get.mockResolvedValue({ data: configsPayload() });
      const store = useAdminDomains();

      const details = await store.fetchConfigs(EXTID);

      expect(mockApi.get).toHaveBeenCalledWith(CONFIGS_URL);
      expect(details?.configs.signin.exists).toBe(true);
      expect(details?.configs.signin.config?.signin_enabled).toBe(true);
      expect(details?.configs.signup.config).toBeNull();
    });

    it('upsertConfig PUTs the kind with the caller-provided body verbatim', async () => {
      mockApi.put.mockResolvedValue({
        data: {
          shrimp: '',
          record: envelopeRecord(),
          details: { kind: 'signin', outcome: 'updated', config: signinConfig() },
        },
      });
      const store = useAdminDomains();

      const details = await store.upsertConfig(EXTID, 'signin', {
        enabled: true,
        restrict_to: null,
      });

      expect(mockApi.put).toHaveBeenCalledWith(`${CONFIGS_URL}/signin`, {
        enabled: true,
        restrict_to: null,
      });
      expect(details?.outcome).toBe('updated');
      expect(details?.kind).toBe('signin');
    });

    it('deleteConfig DELETEs the kind and returns the ack details', async () => {
      mockApi.delete.mockResolvedValue({
        data: {
          shrimp: '',
          record: envelopeRecord(),
          details: { kind: 'mailer', deleted: true },
        },
      });
      const store = useAdminDomains();

      const details = await store.deleteConfig(EXTID, 'mailer');

      expect(mockApi.delete).toHaveBeenCalledWith(`${CONFIGS_URL}/mailer`);
      expect(details?.deleted).toBe(true);
    });

    it('ensureConfigs POSTs dry_run explicitly from the options', async () => {
      mockApi.post.mockResolvedValue({
        data: {
          shrimp: '',
          record: envelopeRecord(),
          details: {
            dry_run: true,
            created: ['signup', 'api'],
            existing: ['signin'],
            skipped: [
              { kind: 'sso', reason: 'requires_credentials' },
              { kind: 'mailer', reason: 'requires_credentials' },
            ],
          },
        },
      });
      const store = useAdminDomains();

      const details = await store.ensureConfigs(EXTID, { dryRun: true });

      expect(mockApi.post).toHaveBeenCalledWith(`${CONFIGS_URL}/ensure`, { dry_run: true });
      expect(details?.dry_run).toBe(true);
      expect(details?.created).toEqual(['signup', 'api']);
    });

    it('resolves null when a 2xx config ack fails the contract', async () => {
      mockApi.put.mockResolvedValue({
        data: { shrimp: '', record: envelopeRecord(), details: { bogus: true } },
      });
      const store = useAdminDomains();

      const details = await store.upsertConfig(EXTID, 'api', { enabled: true });

      expect(details).toBeNull();
    });

    // The kind fields are z.enum tripwires (not bare strings): a backend
    // regression echoing an unexpected slug must fail gracefulParse, not flow
    // into UI logic silently.

    it('resolves null when an ensure ack carries an unknown kind slug', async () => {
      mockApi.post.mockResolvedValue({
        data: {
          shrimp: '',
          record: envelopeRecord(),
          details: { dry_run: true, created: ['telemetry'], existing: [], skipped: [] },
        },
      });
      const store = useAdminDomains();

      const details = await store.ensureConfigs(EXTID, { dryRun: true });

      expect(details).toBeNull();
    });

    it('resolves null when a delete ack carries an unknown kind slug', async () => {
      mockApi.delete.mockResolvedValue({
        data: {
          shrimp: '',
          record: envelopeRecord(),
          details: { kind: 'telemetry', deleted: true },
        },
      });
      const store = useAdminDomains();

      const details = await store.deleteConfig(EXTID, 'mailer');

      expect(details).toBeNull();
    });

    it('resolves null when an upsert ack echoes a non-editable kind', async () => {
      // PUT is gated to the five editable kinds server-side (sso/mailer 422),
      // so an sso echo can only be a backend regression.
      mockApi.put.mockResolvedValue({
        data: {
          shrimp: '',
          record: envelopeRecord(),
          details: { kind: 'sso', outcome: 'updated', config: signinConfig() },
        },
      });
      const store = useAdminDomains();

      const details = await store.upsertConfig(EXTID, 'signin', { enabled: true });

      expect(details).toBeNull();
    });
  });
});
