// e2e/support/mailpit.ts
//
// Mailpit HTTP API helper for suites that need to read a real, delivered
// email instead of stubbing the mail step.
//
// WHY A REAL MAILBOX. Several journeys only mean anything if the link the
// user clicks came from the SERVER: account verification, org invitations,
// magic links, email-change confirmation. A test that fabricates the link
// from a token it already has proves nothing about delivery, about what the
// backend put IN the link, or about what survives opening it in a browser
// that has never seen the original tab.
//
// TARGET. `MAILPIT_URL` (default https://dev.onetime.dev:8025) — the same
// convention e2e/full/org-invitation-flow.spec.ts already documents in its
// header. The local dev Mailpit terminates TLS with the same certificate as
// the app host, so plain fetch() works without a CA override.
//
// SHARED MAILBOX. The dev Mailpit instance is shared across worktrees and
// agents, so nothing here deletes, marks read, or otherwise mutates state
// another run might be relying on. Callers MUST use a unique per-run
// recipient address (see uniqueEmailAddress) — that, not cleanup, is what
// makes a lookup unambiguous.
//
// ASYNC DELIVERY. Mail is enqueued by the web process and delivered by the
// job worker (Onetime::Jobs::Workers::EmailWorker), so a message is NOT in
// the mailbox when the HTTP response lands. Every read here polls.

/** Base URL of the Mailpit instance, no trailing slash. */
export const MAILPIT_URL = (
  process.env.MAILPIT_URL || 'https://dev.onetime.dev:8025'
).replace(/\/+$/, '');

/** Shape of a message summary as returned by GET /api/v1/messages|search. */
interface MailpitAddress {
  Name: string;
  Address: string;
}

interface MailpitSummary {
  ID: string;
  To: MailpitAddress[];
  Subject: string;
  /** RFC3339 timestamp; newest-first is Mailpit's default ordering. */
  Created: string;
}

/** Shape of GET /api/v1/message/{id} — only the fields we read. */
interface MailpitMessage {
  ID: string;
  Subject: string;
  Text?: string;
  HTML?: string;
}

interface MailpitListResponse {
  messages: MailpitSummary[];
}

/** Poll knobs. Generous: the worker's prefetch loop adds seconds, not ms. */
export interface PollOptions {
  /** Total time to keep looking before giving up. Default 30s. */
  timeoutMs?: number;
  /** Gap between attempts. Default 500ms. */
  intervalMs?: number;
}

const DEFAULT_TIMEOUT_MS = 30_000;
const DEFAULT_INTERVAL_MS = 500;

/**
 * A per-run recipient address.
 *
 * Two independent sources of uniqueness — wall clock and randomness — because
 * neither alone is enough: parallel workers can share a millisecond, and a
 * random suffix alone makes a stale mailbox entry indistinguishable from a
 * fresh one when you are eyeballing the Mailpit UI afterwards.
 *
 * The domain is `test.onetimesecret.com`, matching the convention already in
 * e2e/full/org-invitation-flow.spec.ts. It never receives mail; Mailpit
 * accepts every recipient regardless.
 */
export function uniqueEmailAddress(prefix: string): string {
  const stamp = Date.now();
  const salt = Math.random().toString(36).slice(2, 8);
  return `${prefix}-${stamp}-${salt}@test.onetimesecret.com`;
}

/** True when a Mailpit instance is reachable — used to fail with a useful message. */
export async function isMailpitReachable(): Promise<boolean> {
  try {
    const response = await fetch(`${MAILPIT_URL}/api/v1/info`);
    return response.ok;
  } catch {
    return false;
  }
}

async function getJson<T>(path: string): Promise<T> {
  const response = await fetch(`${MAILPIT_URL}${path}`);
  if (!response.ok) {
    throw new Error(
      `Mailpit ${path} responded ${response.status}. ` +
        `Is Mailpit running at ${MAILPIT_URL}? (MAILPIT_URL overrides the default.)`
    );
  }
  return (await response.json()) as T;
}

/**
 * Newest message delivered to `recipient`, or null if the mailbox has none yet.
 *
 * Uses Mailpit's search rather than listing the whole mailbox: the dev
 * instance is shared, so "page 1 of all messages" can be entirely someone
 * else's traffic. Search results come back newest-first, same as the list
 * endpoint.
 */
export async function findLatestMessage(recipient: string): Promise<MailpitSummary | null> {
  const query = encodeURIComponent(`to:${recipient}`);
  const { messages } = await getJson<MailpitListResponse>(
    `/api/v1/search?query=${query}&limit=20`
  );

  // Defensive re-filter: Mailpit's search is substring-based across the
  // envelope, so an unrelated message could match a short address. Compare
  // the parsed recipient list exactly (case-insensitively — SMTP local parts
  // are technically case-sensitive but no real mailer relies on it).
  const target = recipient.toLowerCase();
  const exact = messages.filter((message) =>
    message.To.some((to) => to.Address.toLowerCase() === target)
  );

  return exact[0] ?? null;
}

/** Full message body (Text + HTML) for a message ID. */
export async function fetchMessage(id: string): Promise<MailpitMessage> {
  return getJson<MailpitMessage>(`/api/v1/message/${id}`);
}

/**
 * Waits for a message addressed to `recipient` and returns its full body.
 *
 * @throws when nothing arrives inside the timeout — with the elapsed time and
 *   the target URL in the message, because "no email" has two very different
 *   causes (worker not running vs. mail never enqueued) and the operator needs
 *   to know which one to go look at.
 */
export async function waitForMessage(
  recipient: string,
  options: PollOptions = {}
): Promise<MailpitMessage> {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const intervalMs = options.intervalMs ?? DEFAULT_INTERVAL_MS;
  const deadline = Date.now() + timeoutMs;

  let lastError: unknown = null;

  while (Date.now() < deadline) {
    try {
      const summary = await findLatestMessage(recipient);
      if (summary) return await fetchMessage(summary.ID);
    } catch (error) {
      // A transient network blip should not end the poll; remember it so the
      // timeout message can name it if the blip turns out to be permanent.
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  const suffix = lastError ? ` Last error: ${String(lastError)}` : '';
  throw new Error(
    `No email delivered to ${recipient} within ${timeoutMs}ms via ${MAILPIT_URL}. ` +
      'Check that the app is configured for SMTP delivery (EMAILER_MODE=smtp, ' +
      'SMTP_HOST/SMTP_PORT pointed at Mailpit) AND that the job worker is ' +
      `running — mail is enqueued, not delivered inline.${suffix}`
  );
}

/**
 * Every absolute URL in a message body whose path matches `pathname`.
 *
 * Scans the text part and the HTML part: the HTML template and the plaintext
 * fallback are separate templates and can drift, so a helper that only reads
 * one of them silently stops testing the other.
 */
export function extractLinks(message: MailpitMessage, pathname: string): string[] {
  const haystack = `${message.Text ?? ''}\n${message.HTML ?? ''}`;
  const escaped = pathname.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  // Stop at whitespace, quote, angle bracket or a closing paren — the
  // delimiters an HTML attribute or a Markdown-ish plaintext line can add.
  const pattern = new RegExp(`https?://[^\\s"'<>)]*${escaped}[^\\s"'<>)]*`, 'g');
  const found = haystack.match(pattern) ?? [];

  // De-duplicate: the same link normally appears in BOTH body parts, and a
  // caller asserting "exactly one link" wants one logical link, not two copies.
  return [...new Set(found.map((url) => url.replace(/&amp;/g, '&')))];
}

/**
 * The `/verify-account?key=…` URL from a freshly delivered verification email.
 *
 * Returns the URL as the SERVER wrote it — callers that drive a browser at a
 * different origin (e.g. a Playwright baseURL) should re-base it with
 * `rebaseOnto`, keeping the path and query untouched.
 */
export async function waitForVerificationUrl(
  recipient: string,
  options: PollOptions = {}
): Promise<string> {
  const message = await waitForMessage(recipient, options);
  const links = extractLinks(message, '/verify-account');

  if (links.length === 0) {
    throw new Error(
      `Email to ${recipient} ("${message.Subject}") contains no /verify-account link. ` +
        'The account was probably auto-verified (AUTH_AUTOVERIFY=true) or the ' +
        'verify_account Rodauth feature is off (etc/auth.yaml disables it when ' +
        'RACK_ENV=test).'
    );
  }

  return links[0];
}

/**
 * Re-points an emailed link at the origin the browser is actually using.
 *
 * The verification link is minted from the app's configured HOST, which is
 * not necessarily the Playwright baseURL (container vs. proxied dev host).
 * Path, query and fragment are copied verbatim — rewriting only the origin is
 * the whole point, since the token lives in the query.
 */
export function rebaseOnto(url: string, origin: string): string {
  const source = new URL(url);
  const target = new URL(origin);
  source.protocol = target.protocol;
  source.host = target.host;
  return source.toString();
}
