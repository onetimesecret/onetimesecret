// src/tests/apps/admin/AdminAccountDiagnosticsSection.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createI18n } from 'vue-i18n';

const mockApi = { get: vi.fn(), post: vi.fn(), delete: vi.fn() };
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import AdminAccountDiagnosticsSection from '@/apps/admin/components/AdminAccountDiagnosticsSection.vue';

// Real strings for the two messages under test (the shared test i18n is
// pass-through, which would hide the {reason} interpolation).
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  missingWarn: false,
  fallbackWarn: false,
  missing: (_: unknown, key: string) => key,
  messages: {
    en: {
      web: {
        admin: {
          customers: {
            detail: {
              diagnostics: {
                authUnavailable:
                  'Auth database not available (simple auth mode) — SQL-side checks were skipped.',
                authFailed:
                  'Auth database did not answer, so SQL-side checks could not run: {reason}',
                unknown: 'Unknown',
              },
            },
          },
        },
      },
    },
  },
});

/**
 * Every section key is required by the response schema, so build the full set
 * with the SQL-backed ones degraded — the shape the server sends whenever the
 * authdb is absent or unreachable.
 */
function payload(unavailable: { reason: string; reason_code: string }, findings: unknown[] = []) {
  const degraded = { available: false, ...unavailable };
  return {
    shrimp: '',
    record: { identifier: 'ur_target', found: true },
    details: {
      findings,
      sections: {
        customer: { found: true, email: 'user@example.com' },
        auth_account: degraded,
        mfa: degraded,
        verification: degraded,
        password_reset: degraded,
        lockout: degraded,
        sessions: degraded,
        audit_log: degraded,
        rate_limits: { available: false, reason: 'no email to inspect' },
      },
    },
  };
}

const mountPanel = () =>
  mount(AdminAccountDiagnosticsSection, {
    props: { userId: 'ur_target' },
    global: { plugins: [i18n] },
  });

describe('AdminAccountDiagnosticsSection (unavailable authdb messaging)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const notice = () => wrapper.find('[data-testid="diagnostics-auth-unavailable"]').text();

  it('says simple auth mode when that is why the SQL sections are missing', async () => {
    mockApi.get.mockResolvedValue({
      data: payload({
        reason: 'auth database unavailable (simple auth mode)',
        reason_code: 'simple_mode',
      }),
    });
    wrapper = mountPanel();
    await flushPromises();

    expect(notice()).toContain('simple auth mode');
  });

  // The whole point of the authdb_unavailable finding is "go look at the
  // database". A panel that simultaneously claims simple auth mode sends
  // support in the opposite direction.
  it('does NOT claim simple auth mode when the authdb read failed', async () => {
    mockApi.get.mockResolvedValue({
      data: payload(
        {
          reason: 'auth database error: Sequel::DatabaseConnectionError: could not connect',
          reason_code: 'authdb_error',
        },
        [
          {
            severity: 'critical',
            code: 'authdb_unavailable',
            message: 'The auth database did not answer',
          },
        ]
      ),
    });
    wrapper = mountPanel();
    await flushPromises();

    expect(notice()).not.toContain('simple auth mode');
    expect(notice()).toContain('did not answer');
  });

  it('surfaces the server-supplied reason so the outage is identifiable', async () => {
    mockApi.get.mockResolvedValue({
      data: payload({
        reason: 'auth database error: Sequel::DatabaseConnectionError: could not connect',
        reason_code: 'authdb_error',
      }),
    });
    wrapper = mountPanel();
    await flushPromises();

    expect(notice()).toContain('Sequel::DatabaseConnectionError');
  });

  it('falls back to the failure wording when no reason_code arrives', async () => {
    mockApi.get.mockResolvedValue({
      data: payload({ reason: 'auth database error: boom', reason_code: null as never }),
    });
    wrapper = mountPanel();
    await flushPromises();

    expect(notice()).not.toContain('simple auth mode');
  });

  it('requests the diagnostics endpoint for the given user', async () => {
    mockApi.get.mockResolvedValue({
      data: payload({ reason: 'x', reason_code: 'simple_mode' }),
    });
    wrapper = mountPanel();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/users/ur_target/diagnostics', undefined);
  });
});
