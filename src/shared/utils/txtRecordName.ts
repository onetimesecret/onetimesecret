// src/shared/utils/txtRecordName.ts

/**
 * The TXT ownership record name, as the DNS record panels show it
 * (VerifyDomainDetails, and AdminDomainDnsDetails in the Colonel).
 *
 * The domain API sends three spellings of the record name:
 *
 *   - `txt_validation_host`            relative to `base_domain`, e.g.
 *                                      `_onetime-challenge-abc1234.xn--bcher-kva`.
 *                                      Records from earlier versions may hold
 *                                      the subdomain as typed (Unicode).
 *   - `txt_validation_record`          the full name in A-label form, which is
 *                                      the name the server queries, e.g.
 *                                      `_onetime-challenge-abc1234.xn--bcher-kva.example.com`.
 *   - `txt_validation_record_display`  the full name spelled like
 *                                      `display_domain`, e.g.
 *                                      `_onetime-challenge-abc1234.bücher.example.com`.
 *
 * The panels show the A-label name as a host relative to the zone, followed by
 * the zone, and the copy button copies the host: that is what most DNS
 * providers ask for, and it is how the address record row beside it reads.
 * When the display spelling differs, the panels show it as a hint, since some
 * DNS providers list an internationalised name that way.
 */

/**
 * The domain record fields read here. Structural on purpose: the workspace
 * passes the v3 CustomDomain, the Colonel its own detail record.
 */
export interface TxtRecordNameSource {
  base_domain?: string | null;
  txt_validation_host?: string | null;
  txt_validation_record?: string | null;
  txt_validation_record_display?: string | null;
}

export interface TxtRecordName {
  /** The host to enter at the DNS provider, relative to `zone` when there is one. Copied. */
  host: string;
  /** The zone the host is relative to, with its leading dot (`.example.com`), or undefined. */
  zone: string | undefined;
  /** The full name spelled like `display_domain`, only when it differs from the A-label name. */
  displayName: string | null;
}

/**
 * The challenge label of a TXT validation host: its first label
 * (`_onetime-challenge-abc1234` in `_onetime-challenge-abc1234.secrets`).
 * The label is ASCII however the subdomain after it is spelled.
 */
export function txtChallengeLabel(host: string | null | undefined): string {
  return host?.split('.')[0] ?? '';
}

/**
 * Split the A-label record name into the host relative to `base_domain` and
 * the zone. A-label conversion maps a name label by label, so the host has as
 * many labels as `txt_validation_host` and the zone as many as `base_domain`.
 * When the counts do not add up, or the challenge labels differ, the split
 * cannot be trusted and the full name is returned as the host.
 */
function splitRecordName(
  record: string,
  host: string,
  baseDomain: string
): Pick<TxtRecordName, 'host' | 'zone'> {
  const labels = record.split('.');
  const hostLabelCount = host.split('.').length;
  const fits =
    host !== '' &&
    baseDomain !== '' &&
    labels.length === hostLabelCount + baseDomain.split('.').length &&
    labels[0].toLowerCase() === txtChallengeLabel(host).toLowerCase();

  if (!fits) return { host: record, zone: undefined };

  return {
    host: labels.slice(0, hostLabelCount).join('.'),
    zone: `.${labels.slice(hostLabelCount).join('.')}`,
  };
}

/**
 * The TXT record name to show for a domain. Uses `txt_validation_record`
 * when the server sent one; otherwise falls back to the stored host and
 * `base_domain`, as shown before the server sent the full name.
 */
export function txtRecordName(source: TxtRecordNameSource | null | undefined): TxtRecordName {
  const host = source?.txt_validation_host ?? '';
  const baseDomain = source?.base_domain ?? '';
  const record = source?.txt_validation_record;

  if (!record) {
    return { host, zone: baseDomain ? `.${baseDomain}` : undefined, displayName: null };
  }

  // A-label conversion lowercases; a name that differs only in case is the same name.
  const display = source?.txt_validation_record_display;
  const displayName = display && display.toLowerCase() !== record.toLowerCase() ? display : null;

  return { ...splitRecordName(record, host, baseDomain), displayName };
}
