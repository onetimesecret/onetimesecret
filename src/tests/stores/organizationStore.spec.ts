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

    // The server sync is a protected action (ADR-046#authority-action-gating).
    // The account is named too: a pending selection is noted for one account.
    const CUSTID = 'ur-signed-in';
    const signIn = () => {
      useBootstrapStore().authStatus = 'authenticated';
      useBootstrapStore().custid = CUSTID;
    };

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
      // The objid the note names, or null when there is no note
      const note = (): string | null => {
        const raw = sessionStorage.getItem(PENDING_ORG_SELECTION_KEY);
        return raw ? JSON.parse(raw).objid : null;
      };
      // A note left by an earlier page load, `ageMs` ago, by `custid`
      const leaveNote = (objid: string, ageMs = 0, custid = CUSTID) =>
        sessionStorage.setItem(
          PENDING_ORG_SELECTION_KEY,
          JSON.stringify({ objid, at: Date.now() - ageMs, custid })
        );
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
        it('is sent again when the list loads, and becomes current', async () => {
          signIn();
          leaveNote('org-123');
          axiosMock?.onPost(SYNC_URL).reply(200, { success: true });

          await loadList();

          expect(store.currentOrganization?.objid).toBe('org-123');
          await vi.waitFor(() => expect(note()).toBeNull());
          expect(syncPosts().map((r) => JSON.parse(r.data).organization_id)).toEqual(['org-123']);
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

      it('prefers the default org, then the first', () => {
        store.organizations = [other, { ...mockOrganization, is_default: true }];
        expect(store.defaultOrganization?.objid).toBe('org-123');

        store.organizations = [other, mockOrganization];
        expect(store.defaultOrganization?.objid).toBe('org-999');
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
