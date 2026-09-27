// src/tests/fixtures/bootstrap-wire.ts

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';

/**
 * A fixture as it travels on the WIRE: what the server's JSON actually holds.
 *
 * The scenario fixtures above are shaped like the schema's parsed OUTPUT
 * (`cust.created` is a Date), and JSON cannot carry a Date: the server sends
 * epoch seconds. Anything that stands in for a /bootstrap/me response body or
 * for `window.__BOOTSTRAP_ME__` should go through this, so the contract is
 * exercised against the encoding production uses rather than one it never sees.
 */
export function toWire(payload: BootstrapPayload): Record<string, unknown> {
  const epoch = (value: Date | null | undefined) =>
    value instanceof Date ? Math.floor(value.getTime() / 1000) : null;
  const wire: Record<string, unknown> = { ...payload };
  if (payload.cust) {
    wire.cust = {
      ...payload.cust,
      created: epoch(payload.cust.created),
      updated: epoch(payload.cust.updated),
      last_login: epoch(payload.cust.last_login),
    };
  }
  return JSON.parse(JSON.stringify(wire)) as Record<string, unknown>;
}
