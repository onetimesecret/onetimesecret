// src/shared/utils/domain-host.ts

/**
 * Host normalization shared by every consumer of the bootstrap payload's
 * domain fields.
 *
 * Lives in its own module rather than beside its main caller
 * (`useDomainContext`) so that components which mock the composable wholesale
 * still get the real function — normalizing a hostname is not composable state
 * and there is nothing meaningful to stub.
 */

/**
 * Normalize a host for comparison: trimmed, lowercased, port stripped.
 *
 * The server hands the frontend two families of host strings that are NOT
 * normalized the same way. `link_domains` comes out of DomainStrategy's PARSED
 * canonical set, so it is already lowercased and port-free; `canonical_domain`
 * / `site_host` / `display_domain` are the configured strings verbatim, and
 * `site.host` legally carries a port (the shipped dev default is
 * `localhost:3000`). Comparing the two families raw made every
 * `linkDomains.includes(canonicalDomain)` test fail on a port-bearing
 * canonical host — the single test that decides whether the canonical domain
 * counts as a link-pool member at all.
 *
 * Ruby-side equivalent: `Onetime::Utils::DomainParser.extract_hostname`. Every
 * server endpoint these values are handed to (share_domain,
 * update-domain-context) normalizes the same way, so nothing is lost by
 * normalizing before comparison here.
 *
 * @param host Raw host string from the bootstrap payload, a route param, or
 *   sessionStorage. Nullish and blank inputs normalize to ''.
 */
export function normalizeDomainHost(host: string | null | undefined): string {
  if (!host) return '';
  return host.trim().toLowerCase().replace(/:\d+$/, '');
}
