// src/tests/stores/organizationStore.spec.ts

import { setupTestPinia } from '../setup';
import { setupBootstrapMock } from '../setup-bootstrap';
import { baseBootstrap } from '@/tests/fixtures/bootstrap.fixture';

import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import {
  PENDING_ORG_SELECTION_KEY,
  PENDING_ORG_SELECTION_MAX_AGE_MS,
  useOrganizationStore,
} from '@/shared/stores/organizationStore';
import type { Organization } from '@/types/organization';
import { lenientExtIdSchema, lenientObjIdSchema } from '@/types/identifiers';
import { type AxiosRequestConfig, CanceledError } from 'axios';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';

// Branded-ID helpers: OrganizationInvitation.id/invited_by and
// .organization_id are lenientObjIdSchema/lenientExtIdSchema output
// (see contracts/organization.ts) — plain strings/toObjId/toExtId are a
// structurally-identical but nominally distinct brand and won't assign.
const objId = (raw: string) => lenientObjIdSchema.parse(raw);
const extId = (raw: string) => lenientExtIdSchema.parse(raw);

describe('Organization Store', () => {
  let axiosMock: AxiosMockAdapter | null;
  let store: ReturnType<typeof useOrganizationStore>;

  // Raw API response format (Unix timestamps)
  const mockOrganizationRaw = {
    objid: 'org-123',
    extid: 'on123abc',
    display_name: 'Test Organization',
    description: 'A test organization',
    owner_id: 'cust-456',
    contact_email: 'admin@test.com',
    planid: 'free_v1',
    is_default: false,
    created: Math.floor(new Date('2024-01-01T00:00:00Z').getTime() / 1000),
    updated: Math.floor(new Date('2024-01-01T00:00:00Z').getTime() / 1000),
  };

  // Transformed format (Date objects) for expectations
  const mockOrganization: Organization = {
    objid: 'org-123',
    extid: 'on123abc',
    display_name: 'Test Organization',
    description: 'A test organization',
    owner_id: 'cust-456',
    contact_email: 'admin@test.com',
    planid: 'free_v1',
    is_default: false,
    // Absent on the wire above; the schema normalizes it to false so a payload
    // without the flag never reads as "delete blocked" in the UI.
    active_subscription: false,
    // Absent on the wire above too; normalized to false like is_default.
    is_current_user_default: false,
    created: new Date('2024-01-01T00:00:00Z'),
    updated: new Date('2024-01-01T00:00:00Z'),
  };

  beforeEach(async () => {
    sessionStorage.clear();
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;

    // Setup bootstrap state with modern fixture
    setupBootstrapMock({ initialState: baseBootstrap });
    store = useOrganizationStore();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    if (axiosMock) axiosMock?.reset();
  });

  describe('Initialization', () => {
    it('initializes with empty state', () => {
      store.init();

      expect(store.organizations).toEqual([]);
      expect(store.currentOrganization).toBeNull();
      expect(store.isInitialized).toBe(true);
    });

    it('prevents double initialization', () => {
      const result1 = store.init();
      const result2 = store.init();

      expect(result1).toStrictEqual(result2);
      expect(store.isInitialized).toBe(true);
    });
  });

  describe('Fetching organizations', () => {
    it('fetches all organizations successfully', async () => {
      axiosMock?.onGet('/api/organizations').reply(200, {
        records: [mockOrganizationRaw],
        count: 1,
      });

      await store.fetchOrganizations();

      expect(store.organizations).toHaveLength(1);
      expect(store.organizations[0]).toEqual(mockOrganization);
      expect(store.hasOrganizations).toBe(true);
    });

    it('handles empty organizations response', async () => {
      axiosMock?.onGet('/api/organizations').reply(200, {
        records: [],
        count: 0,
      });

      await store.fetchOrganizations();

      expect(store.organizations).toEqual([]);
      expect(store.hasOrganizations).toBe(false);
    });

    // Route guards that fail closed (handleOrgRoleRequirement) treat a thrown
    // fetch as "access unconfirmed" but a returned empty list as a confirmed
    // "owns no org" refusal. A malformed body must take the thrown path and
    // leave the store as a network rejection would.
    it('rejects on a malformed response and leaves the store untouched', async () => {
      axiosMock?.onGet('/api/organizations').reply(200, {
        records: [mockOrganizationRaw],
        count: 1,
      });
      await store.fetchOrganizations();
      expect(store.organizations).toHaveLength(1);

      axiosMock?.reset();
      axiosMock?.onGet('/api/organizations').reply(200, { records: 'not-an-array' });

      await expect(store.fetchOrganizations()).rejects.toThrow(
        'Unable to load organizations. Please try again.'
      );
      expect(store.organizations).toHaveLength(1);
      expect(store.organizations[0]).toEqual(mockOrganization);
      expect(store.loading).toBe(false);
    });

    it('does not mark the list as fetched when the response is malformed', async () => {
      axiosMock?.onGet('/api/organizations').reply(200, { nope: true });

      await expect(store.fetchOrganizations()).rejects.toThrow();

      expect(store.isListFetched).toBe(false);
      expect(store.organizations).toEqual([]);
    });

    // isListLoading tells a caller whether fetchOrganizations() would cancel
    // a list fetch; `loading` is shared by every action and can't.
    describe('isListLoading', () => {
      /** Hold each list reply until its release() is called */
      const gatedListReplies = () => {
        const releases: Array<() => void> = [];
        axiosMock?.onGet('/api/organizations').reply(
          () =>
            new Promise((resolve) => {
              releases.push(() => resolve([200, { records: [mockOrganizationRaw], count: 1 }]));
            })
        );
        return releases;
      };

      it('is set only while a list fetch is in flight', async () => {
        const releases = gatedListReplies();
        const fetching = store.fetchOrganizations();
        expect(store.isListLoading).toBe(true);

        await vi.waitFor(() => expect(releases).toHaveLength(1));
        releases[0]();
        await fetching;

        expect(store.isListLoading).toBe(false);
      });

      it('stays set when a superseded fetch settles before the one that replaced it', async () => {
        const releases = gatedListReplies();
        const first = store.fetchOrganizations().catch(() => undefined);
        const second = store.fetchOrganizations();

        await vi.waitFor(() => expect(releases).toHaveLength(2));
        releases[0]();
        await first;
        expect(store.isListLoading).toBe(true);

        releases[1]();
        await second;
        expect(store.isListLoading).toBe(false);
      });

      it('is cleared by $reset', async () => {
        const releases = gatedListReplies();
        const fetching = store.fetchOrganizations().catch(() => undefined);
        expect(store.isListLoading).toBe(true);

        store.$reset();
        expect(store.isListLoading).toBe(false);

        await vi.waitFor(() => expect(releases).toHaveLength(1));
        releases[0]();
        await fetching;
        expect(store.isListLoading).toBe(false);
      });

      it('is not set by other store actions', async () => {
        axiosMock?.onGet('/api/organizations/on123abc').reply(200, { record: mockOrganizationRaw });
        const fetching = store.fetchOrganization('on123abc');
        expect(store.loading).toBe(true);
        expect(store.isListLoading).toBe(false);
        await fetching;
      });
    });

    it('fetches a single organization by ID', async () => {
      axiosMock?.onGet('/api/organizations/on123abc').reply(200, {
        record: mockOrganizationRaw,
      });

      const org = await store.fetchOrganization('on123abc');

      expect(org).toEqual(mockOrganization);
      expect(store.currentOrganization).toEqual(mockOrganization);
    });
  });

  // The server session is the one authority for which organization is current
  // across page loads (#4565): the bootstrap payload seeds it, and an explicit
  // choice is written back through update-organization-context. The tab keeps
  // no copy of the selection; sessionStorage holds only a note of a write the
  // server has not answered yet.
  describe('Current organization authority', () => {
    const SYNC_URL = '/api/account/update-organization-context';

    // The bootstrap payload's minimal organization record
    const bootstrapOrg = (over: { objid: string; extid: string; display_name: string }) => ({
      is_default: false,
      planid: 'free_v1',
      current_user_role: 'owner' as const,
      entitlements: null,
      limits: null,
      ...over,
    });
    const acme = bootstrapOrg({ objid: 'org-acme', extid: 'onacme', display_name: 'Acme' });
    const globex = bootstrapOrg({ objid: 'org-globex', extid: 'onglobex', display_name: 'Globex' });

    const other: Organization = {
      ...mockOrganization,
      objid: 'org-999',
      extid: 'on999xyz',
      display_name: 'Other Organization',
    };

    const syncPosts = () => (axiosMock?.history.post ?? []).filter((r) => r.url === SYNC_URL);

    // The objid the pending-selection note names, or null when there is no note
    const note = (): string | null => {
      const raw = sessionStorage.getItem(PENDING_ORG_SELECTION_KEY);
      return raw ? JSON.parse(raw).objid : null;
    };

    // The server sync is a protected action (ADR-046#authority-action-gating).
    // The account is named too: a pending selection is noted for one account.
    const CUSTID = 'ur-signed-in';
    const signIn = () => {
      useBootstrapStore().authStatus = 'authenticated';
      useBootstrapStore().custid = CUSTID;
    };
    // A note left by an earlier page load, `ageMs` ago, by `custid`
    const leaveNote = (objid: string, ageMs = 0, custid = CUSTID) =>
      sessionStorage.setItem(
        PENDING_ORG_SELECTION_KEY,
        JSON.stringify({ objid, at: Date.now() - ageMs, custid })
      );

    describe('seeding from the bootstrap payload', () => {
      it('seeds currentOrganization at store creation', () => {
        // A store created AFTER the payload is in place, as on a page load
        setupBootstrapMock({ initialState: baseBootstrap });
        useBootstrapStore().organization = acme;

        const seeded = useOrganizationStore();

        expect(seeded.currentOrganization).toMatchObject({
          objid: 'org-acme',
          extid: 'onacme',
          display_name: 'Acme',
          current_user_role: 'owner',
        });
      });

      it("carries the bootstrap org's is_current_user_default, false when absent", () => {
        setupBootstrapMock({ initialState: baseBootstrap });
        useBootstrapStore().organization = { ...acme, is_current_user_default: true };
        expect(useOrganizationStore().currentOrganization?.is_current_user_default).toBe(true);

        setupBootstrapMock({ initialState: baseBootstrap });
        useBootstrapStore().organization = acme;
        expect(useOrganizationStore().currentOrganization?.is_current_user_default).toBe(false);
      });

      it('does not replace an existing selection on a bootstrap refresh', async () => {
        store.setCurrentOrganization(other);

        useBootstrapStore().organization = acme;
        await nextTick();

        expect(store.currentOrganization?.objid).toBe('org-999');
      });

      it('re-seeds from the next snapshot after $reset', async () => {
        const bootstrap = useBootstrapStore();
        bootstrap.organization = acme;
        await nextTick();
        expect(store.currentOrganization?.objid).toBe('org-acme');

        // In-place account change: authStore clears account-scoped stores,
        // then applies the new account's snapshot.
        store.$reset();
        expect(store.currentOrganization).toBeNull();
        bootstrap.organization = globex;
        await nextTick();

        expect(store.currentOrganization?.objid).toBe('org-globex');
      });

      it('writes nothing to sessionStorage', async () => {
        useBootstrapStore().organization = acme;
        await nextTick();
        store.setCurrentOrganization(other);
        await nextTick();

        expect(sessionStorage.getItem('selectedOrganizationId')).toBeNull();
        expect(sessionStorage.getItem(PENDING_ORG_SELECTION_KEY)).toBeNull();
      });
    });

    describe('selectOrganization (explicit switch)', () => {
      it('sets the current organization and posts its objid to the server', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(200, { success: true });

        await store.selectOrganization(other);

        expect(store.currentOrganization).toEqual(other);
        expect(syncPosts()).toHaveLength(1);
        // Same identifier the request interceptor sends as O-Organization-ID
        expect(JSON.parse(syncPosts()[0].data)).toEqual({ organization_id: 'org-999' });
      });

      it('switches in-app before the server answers', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(200, { success: true });

        const pending = store.selectOrganization(other);

        expect(store.currentOrganization).toEqual(other);
        await pending;
      });

      it('keeps the in-app selection when the sync fails', async () => {
        signIn();
        const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
        axiosMock?.onPost(SYNC_URL).reply(500, { message: 'boom' });

        await expect(store.selectOrganization(other)).resolves.toBeUndefined();

        expect(store.currentOrganization).toEqual(other);
        expect(syncPosts()).toHaveLength(1);
        expect(warn).toHaveBeenCalledTimes(1);
      });

      it('withholds the server write when protected actions are unavailable', async () => {
        // authStatus is not 'authenticated' here
        await store.selectOrganization(other);

        expect(store.currentOrganization).toEqual(other);
        expect(syncPosts()).toHaveLength(0);
      });

      it('withholds the server write in stale-session mode', async () => {
        signIn();
        useAuthStore().staleSession = true;

        await store.selectOrganization(other);

        expect(store.currentOrganization).toEqual(other);
        expect(syncPosts()).toHaveLength(0);
      });

      // Two writes in flight at once can land on the server in either order,
      // and a reload shows whichever landed last. The store sends the next
      // selection only after the previous reply.
      it('sends a second selection only after the first reply arrives', async () => {
        signIn();
        const events: string[] = [];
        axiosMock?.onPost(SYNC_URL).reply(async (config) => {
          const { organization_id: id } = JSON.parse(config.data);
          events.push(`sent:${id}`);
          // The first reply is the slow one; the second would overtake it
          // if the writes were not serialized.
          await new Promise((resolve) => setTimeout(resolve, id === 'org-999' ? 30 : 0));
          events.push(`replied:${id}`);
          return [200, { success: true }];
        });

        const first = store.selectOrganization(other);
        const second = store.selectOrganization(mockOrganization);
        await Promise.all([first, second]);

        expect(store.currentOrganization).toEqual(mockOrganization);
        expect(events).toEqual([
          'sent:org-999',
          'replied:org-999',
          'sent:org-123',
          'replied:org-123',
        ]);
      });

      it('skips a selection the user moved on from before its turn', async () => {
        signIn();
        const third: Organization = { ...mockOrganization, objid: 'org-333', extid: 'on333abc' };
        axiosMock?.onPost(SYNC_URL).reply(async () => {
          await new Promise((resolve) => setTimeout(resolve, 10));
          return [200, { success: true }];
        });

        await Promise.all([
          store.selectOrganization(other),
          store.selectOrganization(mockOrganization),
          store.selectOrganization(third),
        ]);

        expect(store.currentOrganization).toEqual(third);
        expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual([
          'org-999',
          'org-333',
        ]);
      });

      it('keeps sending later selections after one fails', async () => {
        signIn();
        const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
        axiosMock?.onPost(SYNC_URL).reply((config) => {
          const { organization_id: id } = JSON.parse(config.data);
          return id === 'org-999' ? [500, { message: 'boom' }] : [200, { success: true }];
        });

        await Promise.all([
          store.selectOrganization(other),
          store.selectOrganization(mockOrganization),
        ]);

        expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual([
          'org-999',
          'org-123',
        ]);
        expect(warn).toHaveBeenCalledTimes(1);
      });

      // A reset (logout, in-place account change) must not let a selection
      // queued under the old account go out under the new session.
      it('drops a queued selection when the store is reset', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(async () => {
          await new Promise((resolve) => setTimeout(resolve, 10));
          return [200, { success: true }];
        });

        const first = store.selectOrganization(other);
        const second = store.selectOrganization(mockOrganization);
        store.$reset();
        await Promise.all([first, second]);

        expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual(['org-999']);
      });

      it('sends a selection made after a reset without waiting on the old chain', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(async () => {
          await new Promise((resolve) => setTimeout(resolve, 10));
          return [200, { success: true }];
        });

        const stale = store.selectOrganization(other);
        store.$reset();
        await store.selectOrganization(mockOrganization);

        expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual(['org-999', 'org-123']);
        await stale;
      });

      it('does not send a queued selection once protected actions are unavailable', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(async () => {
          await new Promise((resolve) => setTimeout(resolve, 10));
          return [200, { success: true }];
        });

        const first = store.selectOrganization(other);
        const second = store.selectOrganization(mockOrganization);
        useAuthStore().staleSession = true;
        await Promise.all([first, second]);

        expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual(['org-999']);
      });

      // The withheld selection must not stay queued: a later chain would
      // send it after a newer selection and the server would end on it.
      it('does not send a withheld queued selection after a later one', async () => {
        signIn();
        const third: Organization = { ...mockOrganization, objid: 'org-333', extid: 'on333abc' };
        axiosMock?.onPost(SYNC_URL).reply(async () => {
          await new Promise((resolve) => setTimeout(resolve, 10));
          return [200, { success: true }];
        });

        const first = store.selectOrganization(other);
        const second = store.selectOrganization(mockOrganization);
        useAuthStore().staleSession = true;
        await Promise.all([first, second]);

        useAuthStore().staleSession = false;
        await store.selectOrganization(third);

        expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual([
          'org-999',
          'org-333',
        ]);
      });

      it('syncs a newly created organization, which becomes current', async () => {
        signIn();
        axiosMock?.onPost('/api/organizations').reply(200, { record: mockOrganizationRaw });
        axiosMock?.onPost(SYNC_URL).reply(200, { success: true });

        await store.createOrganization({ display_name: 'Test Organization' });

        expect(store.currentOrganization?.objid).toBe('org-123');
        expect(syncPosts()).toHaveLength(1);
        expect(JSON.parse(syncPosts()[0].data)).toEqual({ organization_id: 'org-123' });
      });
    });

    // A page load can overtake the write: the user reloads before the POST
    // lands, the load reads the old session, and the tab comes back on the
    // previous organization. The newest unanswered selection is noted in
    // sessionStorage so the next page load can send it again.
    describe('a write the server has not answered', () => {
      // When the noted selection was made (epoch ms), or null without a note
      const notedAt = (): number | null => {
        const raw = sessionStorage.getItem(PENDING_ORG_SELECTION_KEY);
        return raw ? JSON.parse(raw).at : null;
      };
      const syncBodies = () => syncPosts().map((r) => JSON.parse(r.data));
      const slowReply =
        (status = 200) =>
        async (): Promise<[number, { success: boolean }]> => {
          await new Promise((resolve) => setTimeout(resolve, 10));
          return [status, { success: status === 200 }];
        };
      const loadList = async () => {
        axiosMock?.onGet('/api/organizations').reply(200, {
          records: [mockOrganizationRaw],
          count: 1,
        });
        await store.fetchOrganizations();
      };

      it('is noted while in flight and settled by the reply', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(slowReply());

        const pending = store.selectOrganization(other);
        expect(note()).toBe('org-999');

        await pending;
        expect(note()).toBeNull();
      });

      it('is sent without an age', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(200, { success: true });

        await store.selectOrganization(other);

        expect(syncBodies()).toEqual([{ organization_id: 'org-999' }]);
      });

      // Without an account to name, the note could be sent as someone else.
      it('is not noted when the account is not known', async () => {
        useBootstrapStore().authStatus = 'authenticated';
        vi.spyOn(console, 'warn').mockImplementation(() => {});
        axiosMock?.onPost(SYNC_URL).networkError();

        await store.selectOrganization(other);

        expect(syncPosts()).toHaveLength(1);
        expect(note()).toBeNull();
      });

      it('is settled by a refusal too', async () => {
        signIn();
        vi.spyOn(console, 'warn').mockImplementation(() => {});
        axiosMock?.onPost(SYNC_URL).reply(422, { message: 'Invalid organization' });

        await store.selectOrganization(other);

        expect(note()).toBeNull();
      });

      it('stays noted when the request gets no answer', async () => {
        signIn();
        vi.spyOn(console, 'warn').mockImplementation(() => {});
        axiosMock?.onPost(SYNC_URL).networkError();

        await store.selectOrganization(other);

        expect(store.currentOrganization).toEqual(other);
        expect(note()).toBe('org-999');
      });

      it('names the newest selection until that one is answered', async () => {
        signIn();
        const notesAtSend: (string | null)[] = [];
        axiosMock?.onPost(SYNC_URL).reply(async (config) => {
          // The second write goes out after the first reply was handled
          if (JSON.parse(config.data).organization_id === 'org-123') notesAtSend.push(note());
          await new Promise((resolve) => setTimeout(resolve, 10));
          return [200, { success: true }];
        });

        const first = store.selectOrganization(other);
        expect(note()).toBe('org-999');
        const second = store.selectOrganization(mockOrganization);
        expect(note()).toBe('org-123');
        await Promise.all([first, second]);

        // The reply to org-999 did not settle the note for org-123.
        expect(notesAtSend).toEqual(['org-123']);
        expect(note()).toBeNull();
      });

      it('is not noted when the write is withheld, and an older note is dropped', async () => {
        leaveNote('org-old');

        // authStatus is not 'authenticated' here
        await store.selectOrganization(other);

        expect(syncPosts()).toHaveLength(0);
        expect(note()).toBeNull();
      });

      it('is dropped when a queued selection is withheld', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(slowReply());

        const first = store.selectOrganization(other);
        const second = store.selectOrganization(mockOrganization);
        useAuthStore().staleSession = true;
        await Promise.all([first, second]);

        expect(note()).toBeNull();
      });

      // The mirror of the queued case above: the newest selection is the
      // withheld one, so the older one still waiting must not go out later.
      it('does not send a queued selection once a newer one was withheld', async () => {
        signIn();
        const third: Organization = { ...mockOrganization, objid: 'org-333', extid: 'on333abc' };
        axiosMock?.onPost(SYNC_URL).reply(slowReply());

        const first = store.selectOrganization(other);
        const second = store.selectOrganization(mockOrganization);
        useAuthStore().staleSession = true;
        await store.selectOrganization(third);
        useAuthStore().staleSession = false;
        await Promise.all([first, second]);

        expect(store.currentOrganization).toEqual(third);
        expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual(['org-999']);
        expect(note()).toBeNull();
      });

      it('goes out unnoted when sessionStorage is unavailable', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(200, { success: true });
        vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
          throw new Error('denied');
        });
        vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
          throw new Error('denied');
        });

        await expect(store.selectOrganization(other)).resolves.toBeUndefined();

        expect(store.currentOrganization).toEqual(other);
        expect(syncPosts()).toHaveLength(1);
      });

      it('is dropped when the store is reset', async () => {
        signIn();
        axiosMock?.onPost(SYNC_URL).reply(slowReply());

        const pending = store.selectOrganization(other);
        store.$reset();

        expect(note()).toBeNull();
        await pending;
        expect(note()).toBeNull();
      });

      // The first successful list fetch of a page load sends the note again.
      describe('after a page load', () => {
        it('is sent again when the list loads, and becomes current once accepted', async () => {
          signIn();
          leaveNote('org-123');
          axiosMock?.onPost(SYNC_URL).reply(slowReply());

          await loadList();

          // Not before the server has accepted it
          expect(store.currentOrganization).toBeNull();
          await vi.waitFor(() => expect(store.currentOrganization?.objid).toBe('org-123'));
          expect(note()).toBeNull();
          expect(syncBodies().map((body) => body.organization_id)).toEqual(['org-123']);
        });

        // The server orders it against selections made since by its age.
        it('is sent with its age, counted from the selection', async () => {
          signIn();
          leaveNote('org-123', 5_000);
          axiosMock?.onPost(SYNC_URL).reply(200, { success: true });

          await loadList();
          await vi.waitFor(() => expect(note()).toBeNull());

          const [body] = syncBodies();
          expect(body.selection_age_ms).toBeGreaterThanOrEqual(5_000);
          expect(body.selection_age_ms).toBeLessThan(10_000);
        });

        it('does not become current when the server refuses it', async () => {
          signIn();
          vi.spyOn(console, 'warn').mockImplementation(() => {});
          leaveNote('org-123');
          axiosMock?.onPost(SYNC_URL).reply(422, { message: 'Selection superseded' });

          await loadList();
          await vi.waitFor(() => expect(note()).toBeNull());

          expect(store.currentOrganization).toBeNull();
          expect(syncPosts()).toHaveLength(1);
        });

        it('does not become current without an answer, and keeps its age', async () => {
          signIn();
          const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
          leaveNote('org-123', 5_000);
          const at = notedAt();
          axiosMock?.onPost(SYNC_URL).networkError();

          await loadList();
          await vi.waitFor(() => expect(warn).toHaveBeenCalledTimes(1));
          await new Promise((resolve) => setTimeout(resolve, 0));

          expect(store.currentOrganization).toBeNull();
          // Still counted from the selection, not from this attempt
          expect(notedAt()).toBe(at);
        });

        it('is dropped, not sent, when another account left it', async () => {
          signIn();
          leaveNote('org-123', 0, 'ur-someone-else');

          await loadList();

          expect(store.currentOrganization).toBeNull();
          expect(syncPosts()).toHaveLength(0);
          expect(note()).toBeNull();
        });

        it('is dropped when it names no account', async () => {
          signIn();
          sessionStorage.setItem(
            PENDING_ORG_SELECTION_KEY,
            JSON.stringify({ objid: 'org-123', at: Date.now() })
          );

          await loadList();

          expect(syncPosts()).toHaveLength(0);
          expect(sessionStorage.getItem(PENDING_ORG_SELECTION_KEY)).toBeNull();
        });

        it('gives way to a selection made while it is on its way', async () => {
          signIn();
          leaveNote('org-123');
          axiosMock?.onPost(SYNC_URL).reply(slowReply());

          await loadList();
          await store.selectOrganization(other);

          expect(store.currentOrganization).toEqual(other);
          expect(syncBodies().map((body) => body.organization_id)).toEqual(['org-123', 'org-999']);
          expect(note()).toBeNull();
        });

        it('does not move a tab the route moved while it was on its way', async () => {
          signIn();
          leaveNote('org-123');
          axiosMock?.onPost(SYNC_URL).reply(slowReply());

          await loadList();
          store.setCurrentOrganization(other);
          await vi.waitFor(() => expect(note()).toBeNull());

          expect(store.currentOrganization).toEqual(other);
        });

        it('is dropped, not sent, when it is too old', async () => {
          signIn();
          leaveNote('org-123', PENDING_ORG_SELECTION_MAX_AGE_MS + 1);

          await loadList();

          expect(store.currentOrganization).toBeNull();
          expect(syncPosts()).toHaveLength(0);
          expect(note()).toBeNull();
        });

        it('is dropped when it is dated in the future', async () => {
          signIn();
          leaveNote('org-123', -60_000);

          await loadList();

          expect(syncPosts()).toHaveLength(0);
          expect(note()).toBeNull();
        });

        it('is dropped when it is unreadable', async () => {
          signIn();
          sessionStorage.setItem(PENDING_ORG_SELECTION_KEY, 'org-123'); // not JSON

          await loadList();

          expect(store.currentOrganization).toBeNull();
          expect(syncPosts()).toHaveLength(0);
          expect(sessionStorage.getItem(PENDING_ORG_SELECTION_KEY)).toBeNull();
        });

        it('is dropped when it names an organization that is not in the list', async () => {
          signIn();
          leaveNote('org-gone');

          await loadList();

          expect(store.currentOrganization).toBeNull();
          expect(syncPosts()).toHaveLength(0);
          expect(note()).toBeNull();
        });

        it('changes nothing without a note', async () => {
          signIn();

          await loadList();

          expect(store.currentOrganization).toBeNull();
          expect(syncPosts()).toHaveLength(0);
        });

        // The tab must not move to a selection the server is not told about.
        it('changes nothing while protected actions are unavailable', async () => {
          signIn();
          useAuthStore().staleSession = true;
          leaveNote('org-123');

          await loadList();

          expect(store.currentOrganization).toBeNull();
          expect(syncPosts()).toHaveLength(0);
          expect(note()).toBe('org-123');
        });

        it('is not sent when the list fails to load', async () => {
          signIn();
          leaveNote('org-123');
          axiosMock?.onGet('/api/organizations').reply(500);

          await expect(store.fetchOrganizations()).rejects.toThrow();

          expect(syncPosts()).toHaveLength(0);
          expect(note()).toBe('org-123');
        });

        it('is sent once per page load', async () => {
          signIn();
          const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
          leaveNote('org-123');
          axiosMock?.onPost(SYNC_URL).networkError();

          await loadList();
          await vi.waitFor(() => expect(warn).toHaveBeenCalledTimes(1));
          // Let the chain finish. Unanswered again, so the note stays for
          // the next page load.
          await new Promise((resolve) => setTimeout(resolve, 0));
          expect(note()).toBe('org-123');

          // A later list fetch in the same page load must not move the tab back
          store.setCurrentOrganization(other);
          await loadList();

          expect(store.currentOrganization).toEqual(other);
          expect(syncPosts()).toHaveLength(1);
        });

        it('leaves a write made in this page load alone', async () => {
          signIn();
          axiosMock?.onPost(SYNC_URL).reply(slowReply());

          const pending = store.selectOrganization(mockOrganization);
          await loadList();
          await pending;

          expect(syncPosts()).toHaveLength(1);
        });
      });
    });

    describe('tab-local changes do not reach the server', () => {
      it('route-driven fetchOrganization does not sync', async () => {
        signIn();
        axiosMock?.onGet('/api/organizations/on123abc').reply(200, { record: mockOrganizationRaw });

        await store.fetchOrganization('on123abc');

        expect(store.currentOrganization?.objid).toBe('org-123');
        expect(syncPosts()).toHaveLength(0);
      });

      it('setCurrentOrganization does not sync', () => {
        signIn();

        store.setCurrentOrganization(other);

        expect(store.currentOrganization).toEqual(other);
        expect(syncPosts()).toHaveLength(0);
      });
    });

    describe('defaultOrganization', () => {
      it('is null with an empty list', () => {
        expect(store.defaultOrganization).toBeNull();
      });

      it("prefers this user's default org, then the first", () => {
        store.organizations = [other, { ...mockOrganization, is_current_user_default: true }];
        expect(store.defaultOrganization?.objid).toBe('org-123');

        store.organizations = [other, mockOrganization];
        expect(store.defaultOrganization?.objid).toBe('org-999');
      });

      // is_default marks the OWNER's auto-created workspace; a member of
      // someone else's default workspace sees it flagged too.
      it("ignores is_default on someone else's default workspace", () => {
        store.organizations = [
          { ...other, is_default: true },
          { ...mockOrganization, is_current_user_default: true },
        ];
        expect(store.defaultOrganization?.objid).toBe('org-123');
      });
    });

    describe('setDefaultOrganization', () => {
      const DEFAULT_URL = '/api/account/update-default-organization';
      const defaultPosts = () =>
        (axiosMock?.history.post ?? []).filter((r) => r.url === DEFAULT_URL);
      // The list as the server returns it once `org-999` is the default
      const listAfter = {
        records: [
          { ...mockOrganizationRaw, is_current_user_default: false },
          {
            ...mockOrganizationRaw,
            objid: 'org-999',
            extid: 'on999xyz',
            display_name: 'Other Organization',
            is_current_user_default: true,
          },
        ],
        count: 2,
      };

      beforeEach(() => {
        store.organizations = [{ ...mockOrganization, is_current_user_default: true }, other];
        store.setCurrentOrganization(store.organizations[0]);
      });

      it('posts the objid, refetches the list, and makes the org current', async () => {
        signIn();
        axiosMock?.onPost(DEFAULT_URL).reply(200, {
          organization_id: 'org-999',
          previous_default_organization_id: 'org-123',
        });
        axiosMock?.onGet('/api/organizations').reply(200, listAfter);

        const result = await store.setDefaultOrganization(other);

        expect(JSON.parse(defaultPosts()[0].data)).toEqual({ organization_id: 'org-999' });
        expect(result).toEqual({
          organization_id: 'org-999',
          previous_default_organization_id: 'org-123',
        });
        expect(store.defaultOrganization?.objid).toBe('org-999');
        expect(store.currentOrganization?.objid).toBe('org-999');
        expect(store.currentOrganization?.is_current_user_default).toBe(true);
        // The server selected it already; nothing is written back
        expect(syncPosts()).toHaveLength(0);
      });

      it('moves the default flag locally when the refetch fails', async () => {
        signIn();
        vi.spyOn(console, 'warn').mockImplementation(() => {});
        axiosMock?.onPost(DEFAULT_URL).reply(200, {
          organization_id: 'org-999',
          previous_default_organization_id: null,
        });
        axiosMock?.onGet('/api/organizations').reply(500);

        await store.setDefaultOrganization(other);

        expect(store.organizations.map((o) => o.is_current_user_default)).toEqual([false, true]);
        expect(store.currentOrganization?.objid).toBe('org-999');
      });

      it('throws and changes nothing when the server refuses', async () => {
        signIn();
        axiosMock?.onPost(DEFAULT_URL).reply(422, { message: 'Invalid organization' });

        await expect(store.setDefaultOrganization(other)).rejects.toBeTruthy();

        expect(store.defaultOrganization?.objid).toBe('org-123');
        expect(store.currentOrganization?.objid).toBe('org-123');
        expect(axiosMock?.history.get ?? []).toHaveLength(0);
      });

      it('throws on a response without the new default', async () => {
        signIn();
        axiosMock?.onPost(DEFAULT_URL).reply(200, { success: true });

        await expect(store.setDefaultOrganization(other)).rejects.toThrow(
          'Unable to update the default organization. Please try again.'
        );
        expect(store.currentOrganization?.objid).toBe('org-123');
      });

      // The server selects the org as well, so the default change and the
      // selection writes share one chain: whichever lands last is what a
      // reload shows, and that must be the user's last choice.
      describe('ordered with selections', () => {
        const third: Organization = {
          ...mockOrganization,
          objid: 'org-333',
          extid: 'on333abc',
          display_name: 'Third Organization',
        };
        const fourth: Organization = { ...third, objid: 'org-444', extid: 'on444abc' };
        const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
        // A promise that settles when `open()` is called, to hold a reply
        const gate = () => {
          let open!: () => void;
          const opened = new Promise<void>((resolve) => {
            open = resolve;
          });
          return { opened, open };
        };
        // Logs each selection write when sent and when answered, which is
        // once `held` settles (10ms without it)
        const logSelections = (events: string[], held?: Promise<void>) =>
          axiosMock?.onPost(SYNC_URL).reply(async (config: AxiosRequestConfig) => {
            const { organization_id: id } = JSON.parse(config.data);
            events.push(`sent:${id}`);
            await (held ?? delay(10));
            events.push(`replied:${id}`);
            return [200, { success: true }];
          });
        // The same for default changes, answered at once without `held`;
        // accepted, or refused with `status`
        const logDefaults = (events: string[], held?: Promise<void>, status = 200) =>
          axiosMock?.onPost(DEFAULT_URL).reply(async (config: AxiosRequestConfig) => {
            const { organization_id: id } = JSON.parse(config.data);
            events.push(`sent:default:${id}`);
            if (held) await held;
            events.push(`replied:default:${id}`);
            return status === 200
              ? [200, { organization_id: id, previous_default_organization_id: 'org-123' }]
              : [status, { message: 'Invalid organization' }];
          });
        const listLoads = () => axiosMock?.history.get ?? [];

        it('is sent only after a selection already on its way is answered', async () => {
          signIn();
          const events: string[] = [];
          logSelections(events);
          logDefaults(events);
          axiosMock?.onGet('/api/organizations').reply(200, listAfter);

          const switching = store.selectOrganization(third);
          await store.setDefaultOrganization(other);
          await switching;

          expect(events).toEqual([
            'sent:org-333',
            'replied:org-333',
            'sent:default:org-999',
            'replied:default:org-999',
          ]);
          expect(store.currentOrganization?.objid).toBe('org-999');
        });

        // The earlier write is still in flight when the later selection is
        // made; it must not take that selection ahead of the default change.
        it('sends a selection made after it, after it', async () => {
          signIn();
          const events: string[] = [];
          logSelections(events);
          logDefaults(events);
          axiosMock?.onGet('/api/organizations').reply(200, listAfter);

          const switching = store.selectOrganization(third);
          const defaulting = store.setDefaultOrganization(other);
          const switchingBack = store.selectOrganization(mockOrganization);
          await Promise.all([switching, defaulting, switchingBack]);

          expect(events).toEqual([
            'sent:org-333',
            'replied:org-333',
            'sent:default:org-999',
            'replied:default:org-999',
            'sent:org-123',
            'replied:org-123',
          ]);
          expect(store.currentOrganization?.objid).toBe('org-123');
        });

        it('keeps a selection made while it is on its way, and its note', async () => {
          signIn();
          const events: string[] = [];
          const defaultHeld = gate();
          const selectionHeld = gate();
          logSelections(events, selectionHeld.opened);
          logDefaults(events, defaultHeld.opened);
          axiosMock?.onGet('/api/organizations').reply(200, listAfter);

          const defaulting = store.setDefaultOrganization(other);
          await vi.waitFor(() => expect(events).toEqual(['sent:default:org-999']));
          const switching = store.selectOrganization(third);
          defaultHeld.open();
          // The default reply has been handled once the list reloads
          await vi.waitFor(() => expect(listLoads()).toHaveLength(1));

          expect(events).toEqual([
            'sent:default:org-999',
            'replied:default:org-999',
            'sent:org-333',
          ]);
          expect(note()).toBe('org-333');

          selectionHeld.open();
          await Promise.all([defaulting, switching]);

          expect(store.currentOrganization).toEqual(third);
          expect(store.defaultOrganization?.objid).toBe('org-999');
          expect(note()).toBeNull();
        });

        it('keeps a selection made while the list reloads', async () => {
          signIn();
          const listHeld = gate();
          logSelections([]);
          logDefaults([]);
          axiosMock?.onGet('/api/organizations').reply(async () => {
            await listHeld.opened;
            return [200, listAfter];
          });

          const defaulting = store.setDefaultOrganization(other);
          await vi.waitFor(() => expect(listLoads()).toHaveLength(1));
          await store.selectOrganization(third);
          listHeld.open();
          await defaulting;

          expect(store.currentOrganization).toEqual(third);
          expect(store.defaultOrganization?.objid).toBe('org-999');
        });

        it('writes nothing once the store is reset while the list reloads', async () => {
          signIn();
          vi.spyOn(console, 'warn').mockImplementation(() => {});
          const listHeld = gate();
          logDefaults([]);
          axiosMock?.onGet('/api/organizations').reply(async () => {
            await listHeld.opened;
            return [200, listAfter];
          });

          const defaulting = store.setDefaultOrganization(other);
          await vi.waitFor(() => expect(listLoads()).toHaveLength(1));
          store.$reset();
          listHeld.open();
          await defaulting;

          expect(store.currentOrganization).toBeNull();
          expect(store.organizations).toEqual([]);
        });

        it('is not sent when the store is reset while it waits its turn', async () => {
          signIn();
          const events: string[] = [];
          logSelections(events);
          logDefaults(events);

          const switching = store.selectOrganization(third);
          const defaulting = store.setDefaultOrganization(other);
          store.$reset();

          // Cancelled, as an aborted request is, rather than refused
          await expect(defaulting).rejects.toBeInstanceOf(CanceledError);
          await switching;
          expect(events).toEqual(['sent:org-333', 'replied:org-333']);
        });

        // Refused, it changes nothing: a selection queued before it still
        // goes out, after the one in flight, as if it had not been made.
        it('leaves a selection queued before it to go out when refused', async () => {
          signIn();
          const events: string[] = [];
          logSelections(events);
          logDefaults(events, undefined, 422);

          const first = store.selectOrganization(third);
          const queued = store.selectOrganization(fourth);
          await expect(store.setDefaultOrganization(other)).rejects.toBeTruthy();
          await Promise.all([first, queued]);

          expect(events).toEqual([
            'sent:org-333',
            'replied:org-333',
            'sent:org-444',
            'replied:org-444',
            'sent:default:org-999',
            'replied:default:org-999',
          ]);
          expect(store.currentOrganization).toEqual(fourth);
          expect(note()).toBeNull();
        });

        // Accepted, it is the newest choice: the queued selection goes out
        // before it, never after.
        it('goes out after a selection queued before it, and wins', async () => {
          signIn();
          const events: string[] = [];
          logSelections(events);
          logDefaults(events);
          axiosMock?.onGet('/api/organizations').reply(200, listAfter);

          const first = store.selectOrganization(third);
          const queued = store.selectOrganization(fourth);
          await store.setDefaultOrganization(other);
          await Promise.all([first, queued]);

          expect(events).toEqual([
            'sent:org-333',
            'replied:org-333',
            'sent:org-444',
            'replied:org-444',
            'sent:default:org-999',
            'replied:default:org-999',
          ]);
          expect(store.currentOrganization?.objid).toBe('org-999');
        });

        // The note left by the last page load is sent again (and moves the
        // tab once accepted) before the default change goes out.
        it('lets a selection sent again before it move the tab when refused', async () => {
          signIn();
          leaveNote('org-999');
          logSelections([]);
          logDefaults([], undefined, 422);
          axiosMock?.onGet('/api/organizations').reply(200, listAfter);

          await store.fetchOrganizations();
          await expect(store.setDefaultOrganization(third)).rejects.toBeTruthy();

          expect(store.currentOrganization?.objid).toBe('org-999');
          expect(note()).toBeNull();
        });

        it('becomes current after a selection sent again before it', async () => {
          signIn();
          leaveNote('org-999');
          logSelections([]);
          logDefaults([]);
          axiosMock?.onGet('/api/organizations').reply(200, listAfter);

          await store.fetchOrganizations();
          await store.setDefaultOrganization(third);

          expect(store.currentOrganization?.objid).toBe('org-333');
        });

        it('leaves the tab to the later of two default changes', async () => {
          signIn();
          vi.spyOn(console, 'warn').mockImplementation(() => {});
          const events: string[] = [];
          logDefaults(events);
          const loads = [gate(), gate()];
          let load = 0;
          axiosMock?.onGet('/api/organizations').reply(async () => {
            await loads[load++].opened;
            return [200, listAfter];
          });

          const first = store.setDefaultOrganization(other);
          const second = store.setDefaultOrganization(third);
          await vi.waitFor(() => expect(listLoads()).toHaveLength(2));
          // The first reload, cut short by the second, ends first
          loads[0].open();
          await first;
          loads[1].open();
          await second;

          expect(events).toEqual([
            'sent:default:org-999',
            'replied:default:org-999',
            'sent:default:org-333',
            'replied:default:org-333',
          ]);
          expect(store.currentOrganization?.objid).toBe('org-333');
        });

        // A fault in one write, not a reply, must not stall those behind it.
        it('sends the writes behind one that throws', async () => {
          signIn();
          vi.spyOn(console, 'warn')
            .mockImplementationOnce(() => {
              throw new Error('broken');
            })
            .mockImplementation(() => {});
          axiosMock?.onPost(SYNC_URL).reply(500, { message: 'boom' });
          logDefaults([]);
          axiosMock?.onGet('/api/organizations').reply(200, listAfter);

          const switching = store.selectOrganization(third);
          const defaulting = store.setDefaultOrganization(other);

          await expect(switching).resolves.toBeUndefined();
          await defaulting;
          expect(defaultPosts()).toHaveLength(1);
          expect(store.currentOrganization?.objid).toBe('org-999');

          await store.selectOrganization(fourth);
          expect(syncPosts()).toHaveLength(2);
        });

        it('still sends a selection queued behind it when the server refuses', async () => {
          signIn();
          logSelections([]);
          axiosMock?.onPost(DEFAULT_URL).reply(422, { message: 'Invalid organization' });

          const defaulting = store.setDefaultOrganization(other);
          const switching = store.selectOrganization(third);

          await expect(defaulting).rejects.toBeTruthy();
          await expect(switching).resolves.toBeUndefined();
          expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual(['org-333']);
          expect(store.currentOrganization).toEqual(third);
        });
      });
    });
  });

  describe('Creating organizations', () => {
    it('creates a new organization successfully', async () => {
      const newOrgPayload = {
        display_name: 'New Organization',
        description: 'A new test organization',
      };

      axiosMock?.onPost('/api/organizations').reply(200, {
        record: mockOrganizationRaw,
      });

      const org = await store.createOrganization(newOrgPayload);

      expect(org).toEqual(mockOrganization);
      expect(store.organizations).toContainEqual(mockOrganization);
      expect(store.currentOrganization).toEqual(mockOrganization);
    });
  });

  describe('Updating organizations', () => {
    beforeEach(async () => {
      store.organizations = [mockOrganization];
      store.currentOrganization = mockOrganization;
    });

    it('updates an organization successfully', async () => {
      const updates = {
        display_name: 'Updated Organization Name',
      };

      const updatedOrgRaw = { ...mockOrganizationRaw, ...updates };

      axiosMock?.onPut('/api/organizations/on123abc').reply(200, {
        record: updatedOrgRaw,
      });

      const result = await store.updateOrganization('on123abc', updates);

      expect(result.display_name).toBe('Updated Organization Name');
      expect(store.organizations[0].display_name).toBe('Updated Organization Name');
      expect(store.currentOrganization?.display_name).toBe('Updated Organization Name');
    });
  });

  describe('Deleting organizations', () => {
    beforeEach(() => {
      store.organizations = [mockOrganization];
      store.currentOrganization = mockOrganization;
    });

    it('deletes an organization successfully', async () => {
      axiosMock?.onDelete('/api/organizations/on123abc').reply(200);

      await store.deleteOrganization('on123abc');

      expect(store.organizations).toEqual([]);
      expect(store.currentOrganization).toBeNull();
    });
  });

  describe('Getters', () => {
    it('computes hasOrganizations correctly', () => {
      expect(store.hasOrganizations).toBe(false);

      store.organizations = [mockOrganization];
      expect(store.hasOrganizations).toBe(true);
    });

    it('finds organization by ID', () => {
      store.organizations = [mockOrganization];

      // getOrganizationById uses internal id (objid), not extid
      const found = store.getOrganizationById('org-123');
      expect(found).toEqual(mockOrganization);

      const notFound = store.getOrganizationById('nonexistent');
      expect(notFound).toBeUndefined();
    });
  });

  describe('Reset functionality', () => {
    it('resets store to initial state', () => {
      store.organizations = [mockOrganization];
      store.currentOrganization = mockOrganization;

      store.$reset();

      expect(store.organizations).toEqual([]);
      expect(store.currentOrganization).toBeNull();
      expect(store._initialized).toBe(false);
    });
  });

  describe('Organization with billing_email', () => {
    it('preserves billing_email in organization data', async () => {
      const orgWithBillingEmail = {
        ...mockOrganizationRaw,
        billing_email: 'billing@example.com',
        contact_email: 'contact@example.com',
      };
      axiosMock?.onGet('/api/organizations/on123abc').reply(200, {
        record: orgWithBillingEmail,
      });

      const org = await store.fetchOrganization('on123abc');

      expect(org.billing_email).toBe('billing@example.com');
      expect(org.contact_email).toBe('contact@example.com');
    });

    it('handles null billing_email gracefully', async () => {
      const orgWithoutBillingEmail = {
        ...mockOrganizationRaw,
        billing_email: null,
        contact_email: 'contact@example.com',
      };
      axiosMock?.onGet('/api/organizations/on123abc').reply(200, {
        record: orgWithoutBillingEmail,
      });

      const org = await store.fetchOrganization('on123abc');

      expect(org.billing_email).toBeNull();
      expect(org.contact_email).toBe('contact@example.com');
    });

    it('handles undefined billing_email gracefully', async () => {
      const orgWithUndefinedBillingEmail = {
        ...mockOrganizationRaw,
        contact_email: 'contact@example.com',
        // billing_email not present in response
      };
      axiosMock?.onGet('/api/organizations/on123abc').reply(200, {
        record: orgWithUndefinedBillingEmail,
      });

      const org = await store.fetchOrganization('on123abc');

      expect(org.billing_email).toBeUndefined();
      expect(org.contact_email).toBe('contact@example.com');
    });
  });

  describe('Organization Invitations', () => {
    // Mock invitation data
    const mockInvitationRaw = {
      id: 'inv-123',
      organization_id: 'org-123',
      email: 'invitee@example.com',
      role: 'member' as const,
      status: 'pending' as const,
      invited_by: 'owner@example.com',
      invited_at: Math.floor(new Date('2024-01-01T00:00:00Z').getTime() / 1000),
      expires_at: Math.floor(new Date('2024-01-08T00:00:00Z').getTime() / 1000),
      resend_count: 0,
      token: 'secure-token-abc123',
    };

    const mockInvitationRaw2 = {
      id: 'inv-456',
      organization_id: 'org-123',
      email: 'another@example.com',
      role: 'admin' as const,
      status: 'pending' as const,
      invited_by: 'owner@example.com',
      invited_at: Math.floor(new Date('2024-01-02T00:00:00Z').getTime() / 1000),
      expires_at: Math.floor(new Date('2024-01-09T00:00:00Z').getTime() / 1000),
      resend_count: 1,
      token: 'secure-token-def456',
    };

    describe('fetchInvitations', () => {
      it('fetches invitations for an organization successfully', async () => {
        axiosMock?.onGet('/api/organizations/on123abc/invitations').reply(200, {
          records: [mockInvitationRaw, mockInvitationRaw2],
        });

        const invitations = await store.fetchInvitations('on123abc');

        expect(invitations).toHaveLength(2);
        expect(store.invitations).toHaveLength(2);
        expect(invitations[0].email).toBe('invitee@example.com');
        expect(invitations[0].role).toBe('member');
        expect(invitations[1].email).toBe('another@example.com');
        expect(invitations[1].role).toBe('admin');
      });

      it('handles empty invitations response', async () => {
        axiosMock?.onGet('/api/organizations/on123abc/invitations').reply(200, {
          records: [],
        });

        const invitations = await store.fetchInvitations('on123abc');

        expect(invitations).toEqual([]);
        expect(store.invitations).toEqual([]);
      });

      it('validates invitation data with schema', async () => {
        axiosMock?.onGet('/api/organizations/on123abc/invitations').reply(200, {
          records: [mockInvitationRaw],
        });

        const invitations = await store.fetchInvitations('on123abc');

        expect(invitations[0]).toMatchObject({
          id: 'inv-123',
          organization_id: 'org-123',
          email: 'invitee@example.com',
          role: 'member',
          status: 'pending',
          invited_by: 'owner@example.com',
          resend_count: 0,
          token: 'secure-token-abc123',
        });
      });

      it('sets loading state during fetch', async () => {
        let resolveRequest: (value: unknown) => void;
        const requestPromise = new Promise((resolve) => {
          resolveRequest = resolve;
        });

        axiosMock?.onGet('/api/organizations/on123abc/invitations').reply(async () => {
          await requestPromise;
          return [200, { records: [mockInvitationRaw] }];
        });

        const fetchPromise = store.fetchInvitations('on123abc');
        expect(store.loading).toBe(true);

        resolveRequest!(undefined);
        await fetchPromise;

        expect(store.loading).toBe(false);
      });
    });

    describe('createInvitation', () => {
      it('creates an invitation successfully', async () => {
        const payload = {
          email: 'newmember@example.com',
          role: 'member' as const,
        };

        const createdInvitationRaw = {
          ...mockInvitationRaw,
          id: 'inv-new',
          email: 'newmember@example.com',
        };

        axiosMock?.onPost('/api/organizations/on123abc/invitations').reply(200, {
          record: createdInvitationRaw,
        });

        const invitation = await store.createInvitation('on123abc', payload);

        expect(invitation.email).toBe('newmember@example.com');
        expect(invitation.role).toBe('member');
        expect(store.invitations).toContainEqual(
          expect.objectContaining({ email: 'newmember@example.com' })
        );
      });

      it('creates an admin invitation', async () => {
        const payload = {
          email: 'newadmin@example.com',
          role: 'admin' as const,
        };

        const createdInvitationRaw = {
          ...mockInvitationRaw,
          id: 'inv-admin',
          email: 'newadmin@example.com',
          role: 'admin' as const,
        };

        axiosMock?.onPost('/api/organizations/on123abc/invitations').reply(200, {
          record: createdInvitationRaw,
        });

        const invitation = await store.createInvitation('on123abc', payload);

        expect(invitation.email).toBe('newadmin@example.com');
        expect(invitation.role).toBe('admin');
      });

      it('adds created invitation to store invitations array', async () => {
        // Pre-populate with existing invitation
        store.invitations = [
          {
            id: objId('inv-existing'),
            organization_id: extId('org-123'),
            email: 'existing@example.com',
            role: 'member',
            status: 'pending',
            invited_by: objId('owner@example.com'),
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
          },
        ];

        const payload = {
          email: 'new@example.com',
          role: 'member' as const,
        };

        axiosMock?.onPost('/api/organizations/on123abc/invitations').reply(200, {
          record: { ...mockInvitationRaw, email: 'new@example.com' },
        });

        await store.createInvitation('on123abc', payload);

        expect(store.invitations).toHaveLength(2);
      });

      it('validates payload before sending', async () => {
        const invalidPayload = {
          email: 'invalid-email',
          role: 'member' as const,
        };

        await expect(store.createInvitation('on123abc', invalidPayload)).rejects.toThrow();
      });

      it('sets loading state during creation', async () => {
        const payload = {
          email: 'test@example.com',
          role: 'member' as const,
        };

        let resolveRequest: (value: unknown) => void;
        const requestPromise = new Promise((resolve) => {
          resolveRequest = resolve;
        });

        axiosMock?.onPost('/api/organizations/on123abc/invitations').reply(async () => {
          await requestPromise;
          return [200, { record: mockInvitationRaw }];
        });

        const createPromise = store.createInvitation('on123abc', payload);
        expect(store.loading).toBe(true);

        resolveRequest!(undefined);
        await createPromise;

        expect(store.loading).toBe(false);
      });
    });

    describe('resendInvitation', () => {
      beforeEach(() => {
        // Pre-populate with invitation
        store.invitations = [
          {
            id: objId('inv-123'),
            organization_id: extId('org-123'),
            email: 'invitee@example.com',
            role: 'member',
            status: 'pending',
            invited_by: objId('owner@example.com'),
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
            token: 'secure-token-abc123',
          },
        ];
      });

      it('resends an invitation successfully', async () => {
        // Mock the resend endpoint
        axiosMock
          ?.onPost('/api/organizations/on123abc/invitations/secure-token-abc123/resend')
          .reply(200, {});

        // Mock the refresh fetch with updated resend count
        axiosMock?.onGet('/api/organizations/on123abc/invitations').reply(200, {
          records: [{ ...mockInvitationRaw, resend_count: 1 }],
        });

        await store.resendInvitation('on123abc', 'secure-token-abc123');

        // Should have refreshed invitations
        expect(store.invitations[0].resend_count).toBe(1);
      });

      it('sets loading state during resend', async () => {
        let resolveRequest: (value: unknown) => void;
        const requestPromise = new Promise((resolve) => {
          resolveRequest = resolve;
        });

        axiosMock
          ?.onPost('/api/organizations/on123abc/invitations/secure-token-abc123/resend')
          .reply(async () => {
            await requestPromise;
            return [200, {}];
          });

        axiosMock?.onGet('/api/organizations/on123abc/invitations').reply(200, {
          records: [mockInvitationRaw],
        });

        const resendPromise = store.resendInvitation('on123abc', 'secure-token-abc123');
        expect(store.loading).toBe(true);

        resolveRequest!(undefined);
        await resendPromise;

        expect(store.loading).toBe(false);
      });
    });

    describe('revokeInvitation', () => {
      beforeEach(() => {
        // Pre-populate with invitations
        store.invitations = [
          {
            id: objId('inv-123'),
            organization_id: extId('org-123'),
            email: 'invitee@example.com',
            role: 'member',
            status: 'pending',
            invited_by: objId('owner@example.com'),
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
            token: 'token-to-revoke',
          },
          {
            id: objId('inv-456'),
            organization_id: extId('org-123'),
            email: 'another@example.com',
            role: 'admin',
            status: 'pending',
            invited_by: objId('owner@example.com'),
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
            token: 'token-to-keep',
          },
        ];
      });

      it('revokes an invitation successfully', async () => {
        axiosMock
          ?.onDelete('/api/organizations/on123abc/invitations/token-to-revoke')
          .reply(200, {});

        await store.revokeInvitation('on123abc', 'token-to-revoke');

        expect(store.invitations).toHaveLength(1);
        expect(store.invitations[0].token).toBe('token-to-keep');
      });

      it('removes revoked invitation from store', async () => {
        axiosMock
          ?.onDelete('/api/organizations/on123abc/invitations/token-to-revoke')
          .reply(200, {});

        const initialCount = store.invitations.length;
        await store.revokeInvitation('on123abc', 'token-to-revoke');

        expect(store.invitations).toHaveLength(initialCount - 1);
        expect(store.invitations.find((inv) => inv.token === 'token-to-revoke')).toBeUndefined();
      });

      it('sets loading state during revoke', async () => {
        let resolveRequest: (value: unknown) => void;
        const requestPromise = new Promise((resolve) => {
          resolveRequest = resolve;
        });

        axiosMock
          ?.onDelete('/api/organizations/on123abc/invitations/token-to-revoke')
          .reply(async () => {
            await requestPromise;
            return [200, {}];
          });

        const revokePromise = store.revokeInvitation('on123abc', 'token-to-revoke');
        expect(store.loading).toBe(true);

        resolveRequest!(undefined);
        await revokePromise;

        expect(store.loading).toBe(false);
      });
    });

    describe('Invitation state management', () => {
      it('clears invitations on store reset', () => {
        store.invitations = [
          {
            id: objId('inv-123'),
            organization_id: extId('org-123'),
            email: 'test@example.com',
            role: 'member',
            status: 'pending',
            invited_by: objId('owner@example.com'),
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
          },
        ];

        store.$reset();

        expect(store.invitations).toEqual([]);
      });
    });
  });
});
