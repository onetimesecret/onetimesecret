// src/shared/utils/aLabelName.ts

/**
 * Split a DNS name the server sent in A-label form into the host a DNS
 * provider asks for and the zone the host is relative to.
 *
 * CustomDomain stores names as the customer typed them, and the server sends
 * the A-label forms beside them (`display_domain_ascii`,
 * `txt_validation_record`). The frontend does not convert names itself, so it
 * cannot disagree with the server's conversion. It only has to find where the
 * host ends in the A-label name, and it reads that off the typed spellings:
 * A-label conversion maps a name label by label, so the A-label name has as
 * many labels as the typed host and the typed zone together. Label separators
 * other than "." (U+3002 and its relatives) are mapped to "." and break that
 * count, so the count is checked, and so is every ASCII label of the typed
 * spelling, which conversion only lowercases.
 *
 * Used by txtRecordName (the TXT ownership record) and useDomainDnsRecord
 * (the address record).
 */

export interface ALabelNameSplit {
  /** The labels before the zone; '' when the name is the zone itself. */
  host: string;
  /** The zone, without a leading dot. */
  zone: string;
}

const isAscii = (text: string): boolean =>
  [...text].every((char) => (char.codePointAt(0) ?? 0) < 0x80);

/**
 * @param aLabelName The full name in A-label form, as the server sent it.
 * @param typedHost  The typed host relative to the zone; '' for the zone itself.
 * @param typedZone  The typed zone (base_domain).
 * @returns The A-label host and zone, or null when the A-label name does not
 *   line up with the typed spellings and the split cannot be trusted.
 */
export function splitALabelName(
  aLabelName: string,
  typedHost: string,
  typedZone: string
): ALabelNameSplit | null {
  if (!aLabelName || !typedZone) return null;

  const zoneLabelCount = typedZone.split('.').length;
  const typedLabels = [...(typedHost ? typedHost.split('.') : []), ...typedZone.split('.')];
  const labels = aLabelName.split('.');

  if (labels.length !== typedLabels.length) return null;
  const consistent = typedLabels.every(
    (typed, i) => !isAscii(typed) || typed.toLowerCase() === labels[i].toLowerCase()
  );
  if (!consistent) return null;

  const hostLabelCount = labels.length - zoneLabelCount;
  return {
    host: labels.slice(0, hostLabelCount).join('.'),
    zone: labels.slice(hostLabelCount).join('.'),
  };
}

/**
 * Whether a typed spelling differs from the A-label name beyond case, i.e.
 * whether showing it beside the A-label name tells the reader anything.
 * A-label conversion lowercases, so a name that differs only in case is the
 * same name.
 */
export function spellingDiffers(
  typed: string | null | undefined,
  aLabelName: string | null | undefined
): boolean {
  return !!typed && !!aLabelName && typed.toLowerCase() !== aLabelName.toLowerCase();
}
