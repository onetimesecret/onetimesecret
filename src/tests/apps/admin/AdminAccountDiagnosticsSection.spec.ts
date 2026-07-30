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

// Real strings for the messages under test (the shared test i18n is
// pass-through, which would hide the {reason} interpolation and make every
// degraded cell indistinguishable from every other).
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
                facts: {
                  authStatus: 'Auth status',
                  noAccount: 'No auth account',
                  password: 'Password',
                  passwordSet: 'Set',
                  passwordNone: 'None',
                  mfa: 'MFA',
                  mfaNone: 'None',
                  loginFailures: 'Failed attempts',
                  lockedBadge: 'Locked out',
                  rateLimiter: 'Rate limiter',
                  rateLimiterEngaged: 'Engaged',
                  rateLimiterClear: 'Clear',
                  verification: 'Verification email',
                  verificationPending: 'Pending — last sent {date}',
                  verificationNone: 'None pending',
                  sessions: 'Active sessions',
                  lastLogin: 'Last login (auth)',
                },
                auditLog: {
                  title: 'Authentication log',
                  empty: 'No authentication events recorded.',
                  unavailable: 'Authentication log could not be read: {reason}',
                },
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

const SIDECAR_FAILURE = {
  available: false,
  reason: 'Sequel::DatabaseDisconnectError: connection reset by peer',
};

const LIVE_AUTH_ACCOUNT = {
  available: true,
  found: true,
  account_id: 42,
  status: 'Verified',
  email: 'user@example.com',
  has_password: true,
  last_login_at: 1_752_000_000,
};

/**
 * The shape the server sends when `auth_account` answered but a later SQL read
 * did not (connection drop, statement timeout, ungranted sidecar table — see
 * Diagnose#section, which merges `available: true` per section) plus
 * `rate_limits`, which degrades independently of the authdb whenever there is
 * no email to key on. This is the payload the grid renders, so every cell must
 * carry its own guard.
 */
function partialPayload(
  authAccount: Record<string, unknown> = LIVE_AUTH_ACCOUNT,
  overrides: Record<string, unknown> = {}
) {
  return {
    shrimp: '',
    record: { identifier: 'ur_target', found: true },
    details: {
      findings: [],
      sections: {
        customer: { found: true, email: 'user@example.com' },
        auth_account: authAccount,
        mfa: { ...SIDECAR_FAILURE },
        verification: { ...SIDECAR_FAILURE },
        password_reset: { ...SIDECAR_FAILURE },
        lockout: { ...SIDECAR_FAILURE },
        sessions: { ...SIDECAR_FAILURE },
        audit_log: { ...SIDECAR_FAILURE },
        rate_limits: { available: false, reason: 'no email to inspect' },
        ...overrides,
      },
    },
  };
}

/** Everything answered — the control that proves "Unknown" is conditional. */
function healthyPayload() {
  return partialPayload(LIVE_AUTH_ACCOUNT, {
    mfa: { available: true, otp_enabled: true, webauthn_credentials: 0 },
    verification: { available: true, pending: true, email_last_sent: 1_752_000_000 },
    password_reset: { available: true, pending: false },
    lockout: { available: true, login_failures: 3, locked: true },
    sessions: { available: true, active_count: 2 },
    audit_log: { available: true, entries: [{ at: 1_752_000_000, message: 'login' }] },
    rate_limits: {
      available: true,
      entries: [{ key: 'login:locked:user@example.com', ttl: 900, value: '1', exists: true }],
    },
  });
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

/**
 * The grid only hides when `auth_account` itself is unavailable, so these are
 * the shapes where it renders values for reads that FAILED. A concrete "0" or
 * "Clear" here is read as a negative assertion ("not locked out", "no limiter
 * hit") and sends support looking somewhere else.
 */
describe('AdminAccountDiagnosticsSection (partially degraded sections)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const cell = (name: string) => wrapper.find(`[data-testid="diagnostics-fact-${name}"]`).text();

  const mountWith = async (data: unknown) => {
    mockApi.get.mockResolvedValue({ data });
    wrapper = mountPanel();
    await flushPromises();
  };

  it('renders the fact grid when auth_account answered but sidecar reads failed', async () => {
    await mountWith(partialPayload());

    expect(wrapper.find('[data-testid="diagnostics-facts"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="diagnostics-auth-unavailable"]').exists()).toBe(false);
  });

  it('says Unknown, not "0", for failed attempts when the lockout read failed', async () => {
    await mountWith(partialPayload());

    expect(cell('login-failures')).toBe('Unknown');
  });

  it('withholds the "Locked out" badge when the lockout read failed', async () => {
    await mountWith(partialPayload());

    expect(cell('login-failures')).not.toContain('Locked out');
  });

  it('says Unknown, not "Clear", when the rate-limiter section is unavailable', async () => {
    await mountWith(partialPayload());

    expect(cell('rate-limiter')).toBe('Unknown');
  });

  it('says Unknown, not "None pending", when the verification read failed', async () => {
    await mountWith(partialPayload());

    expect(cell('verification')).toBe('Unknown');
  });

  it('says Unknown, not "0", for active sessions when the sessions read failed', async () => {
    await mountWith(partialPayload());

    expect(cell('sessions')).toBe('Unknown');
  });

  it('reports the audit-log failure and its reason instead of "no events recorded"', async () => {
    await mountWith(partialPayload());

    const message = wrapper.find('[data-testid="diagnostics-audit-log-unavailable"]');
    expect(message.exists()).toBe(true);
    expect(message.text()).toContain('could not be read');
    expect(message.text()).toContain('Sequel::DatabaseDisconnectError');
    expect(wrapper.find('[data-testid="diagnostics-audit-log-empty"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="diagnostics-audit-log"]').exists()).toBe(false);
  });

  it('falls back to Unknown in the audit-log message when no reason arrives', async () => {
    await mountWith(partialPayload(LIVE_AUTH_ACCOUNT, { audit_log: { available: false } }));

    expect(wrapper.find('[data-testid="diagnostics-audit-log-unavailable"]').text()).toContain(
      'Unknown'
    );
  });

  // Control: the guards must not turn every cell into "Unknown".
  it('prints the concrete values when every section answered', async () => {
    await mountWith(healthyPayload());

    expect(cell('login-failures')).toContain('3');
    expect(cell('login-failures')).toContain('Locked out');
    expect(cell('rate-limiter')).toBe('Engaged');
    expect(cell('verification')).toContain('Pending');
    expect(cell('sessions')).toBe('2');
    expect(cell('password')).toBe('Set');
    expect(wrapper.find('[data-testid="diagnostics-audit-log"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="diagnostics-audit-log-unavailable"]').exists()).toBe(false);
  });

  it('shows the empty-log wording when the audit log answered with no entries', async () => {
    await mountWith(
      partialPayload(LIVE_AUTH_ACCOUNT, { audit_log: { available: true, entries: [] } })
    );

    expect(wrapper.find('[data-testid="diagnostics-audit-log-empty"]').text()).toContain(
      'No authentication events recorded.'
    );
    expect(wrapper.find('[data-testid="diagnostics-audit-log-unavailable"]').exists()).toBe(false);
  });
});

/**
 * A section can also reach the panel with `available` ABSENT — not false,
 * missing. The wire schema marks the flag optional on purpose (a required
 * field would make a version-skewed payload fail validation, and
 * useResourceFetch answers a parse failure by discarding the response, which
 * blanks the whole break-glass panel during the incident it exists to triage).
 * The cost of that choice is paid in the consumer: the guard is fail-closed,
 * so a missing flag degrades one cell to "Unknown" instead of printing the
 * same reassuring zero a successful read would.
 */
describe('AdminAccountDiagnosticsSection (section arrives without `available`)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const cell = (name: string) => wrapper.find(`[data-testid="diagnostics-fact-${name}"]`).text();

  const mountWith = async (data: unknown) => {
    mockApi.get.mockResolvedValue({ data });
    wrapper = mountPanel();
    await flushPromises();
  };

  /**
   * Every value here is the benign one ("0 failures", "no limiter key", "no
   * pending verification"), which is exactly what makes the shape dangerous:
   * nothing in it says the read succeeded.
   */
  const flaglessPayload = () =>
    partialPayload(LIVE_AUTH_ACCOUNT, {
      mfa: { otp_enabled: false, webauthn_credentials: 0 },
      verification: { pending: false },
      password_reset: { pending: false },
      lockout: { login_failures: 0, locked: false },
      sessions: { active_count: 0 },
      audit_log: { entries: [] },
      rate_limits: { entries: [] },
    });

  it('still renders the panel — a missing flag is not a contract failure', async () => {
    await mountWith(flaglessPayload());

    expect(wrapper.find('[data-testid="diagnostics-section-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="diagnostics-facts"]').exists()).toBe(true);
  });

  it('says Unknown for every cell whose section omitted the flag', async () => {
    await mountWith(flaglessPayload());

    expect(cell('login-failures')).toBe('Unknown');
    expect(cell('sessions')).toBe('Unknown');
    expect(cell('rate-limiter')).toBe('Unknown');
    expect(cell('verification')).toBe('Unknown');
  });

  it('treats the audit log as unread, not as empty', async () => {
    await mountWith(flaglessPayload());

    expect(wrapper.find('[data-testid="diagnostics-audit-log-unavailable"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="diagnostics-audit-log-empty"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="diagnostics-audit-log"]').exists()).toBe(false);
  });

  // The grid gate stays "explicitly false" deliberately: fail-closing it would
  // hide the fact grid and the log, and the accompanying copy asserts an authdb
  // outage — a cause we have no evidence for when a field is merely absent.
  it('keeps the grid visible when auth_account itself omits the flag', async () => {
    await mountWith(partialPayload({ found: true, status: 'Verified', has_password: true }));

    expect(wrapper.find('[data-testid="diagnostics-facts"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="diagnostics-auth-unavailable"]').exists()).toBe(false);
  });

  it('withholds auth_account values it cannot vouch for', async () => {
    await mountWith(partialPayload({ found: true, status: 'Verified', has_password: true }));

    expect(cell('password')).toBe('Unknown');
    expect(cell('auth-status')).toBe('Unknown');
  });
});

/**
 * The `no_account` path (Diagnose#authdb_sections) degrades every SQL section
 * but merges `auth_account: { available: true, found: false }` — available, so
 * the grid renders against an account row that does not exist. "None" would
 * claim we looked at a password field; there is no row to look at.
 */
describe('AdminAccountDiagnosticsSection (no auth account row)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const mountOrphan = async () => {
    mockApi.get.mockResolvedValue({
      data: partialPayload({ available: true, found: false }),
    });
    wrapper = mountPanel();
    await flushPromises();
  };

  it('says "No auth account" for the password cell, not "None"', async () => {
    await mountOrphan();

    const password = wrapper.find('[data-testid="diagnostics-fact-password"]').text();
    expect(password).toBe('No auth account');
    expect(password).not.toBe('None');
  });

  it('still reports the auth status as having no account', async () => {
    await mountOrphan();

    expect(wrapper.find('[data-testid="diagnostics-facts"]').text()).toContain('No auth account');
  });
});
