// src/utils/parse/domain.ts

/**
 * Client-side domain-parsing guidance utility.
 *
 * Decides whether a typed hostname is a subdomain, an apex (registrable)
 * domain, or invalid. This is a pure, dependency-free heuristic used only to
 * guide the UX — the server (Ruby PublicSuffix) remains the authoritative
 * validator. Intentionally does NOT pull in `psl` or any npm package.
 */

/**
 * Curated set of common two-level ICANN public suffixes.
 *
 * This is a heuristic for UX guidance only, NOT an exhaustive public suffix
 * list. It covers a solid international spread of frequently-used two-level
 * suffixes so that e.g. "acme.co.uk" is treated as an apex domain rather than
 * a subdomain of "co.uk". The server-side Ruby PublicSuffix library is the
 * authoritative source of truth; when this Set disagrees with the server, the
 * server wins.
 */
const MULTI_PART_SUFFIXES = new Set<string>([
  // United Kingdom
  'co.uk', 'org.uk', 'gov.uk', 'ac.uk', 'me.uk', 'ltd.uk', 'plc.uk', 'net.uk', 'sch.uk',
  // Australia
  'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au', 'id.au',
  // New Zealand
  'co.nz', 'net.nz', 'org.nz', 'govt.nz', 'ac.nz', 'school.nz',
  // Japan
  'co.jp', 'or.jp', 'ne.jp', 'go.jp', 'ac.jp',
  // Brazil
  'com.br', 'net.br', 'org.br', 'gov.br',
  // South Africa
  'co.za', 'org.za', 'net.za', 'gov.za',
  // India
  'co.in', 'net.in', 'org.in', 'gen.in', 'firm.in', 'ind.in', 'gov.in',
  // Mexico
  'com.mx', 'org.mx', 'gob.mx',
  // Singapore
  'com.sg', 'edu.sg', 'gov.sg', 'net.sg', 'org.sg',
  // China
  'com.cn', 'net.cn', 'org.cn', 'gov.cn',
  // South Korea
  'co.kr', 'or.kr', 'go.kr',
  // Hong Kong
  'com.hk', 'org.hk', 'edu.hk', 'gov.hk',
  // Taiwan
  'com.tw', 'org.tw', 'gov.tw',
  // Israel
  'co.il', 'org.il', 'gov.il', 'ac.il',
  // Turkey
  'com.tr', 'org.tr', 'gov.tr',
  // Argentina
  'com.ar', 'gob.ar', 'org.ar',
  // Indonesia
  'co.id', 'or.id', 'go.id',
  // Malaysia
  'com.my', 'org.my', 'gov.my',
  // Philippines
  'com.ph', 'org.ph', 'gov.ph',
  // Pakistan
  'com.pk', 'org.pk', 'gov.pk',
  // Ukraine
  'com.ua', 'co.ua',
  // Colombia
  'com.co', 'net.co', 'org.co',
  // Nigeria
  'com.ng', 'org.ng', 'gov.ng',
  // Saudi Arabia
  'com.sa', 'org.sa', 'gov.sa',
  // Vietnam
  'com.vn', 'net.vn', 'org.vn',
  // Thailand
  'co.th', 'in.th', 'or.th', 'go.th',
  // Kenya
  'co.ke', 'or.ke', 'go.ke',
  // Assorted Latin American commercial suffixes
  'com.ec', 'com.pe', 'com.uy', 'com.ve', 'com.do', 'com.gt', 'com.py', 'com.bo',
]);

export interface DomainAnalysis {
  empty: boolean;        // trimmed input is empty
  valid: boolean;        // a usable registrable domain OR a deeper hostname
  apex: boolean;         // input is exactly the registrable domain (or www.<registrable>)
  registrable: string;   // e.g. "acme.com" / "acme.co.uk"; '' when invalid
  subdomain: string;     // labels left of registrable, e.g. "secrets"; '' for apex
  full: string;          // cleaned input hostname
  reason: null | 'malformed' | 'suffix';
  tld: string;           // public suffix, e.g. "com" / "co.uk"; '' when unknown
}

/**
 * Normalize a raw hostname string: trim, lowercase, strip an optional
 * http(s):// scheme, drop any path, and remove a single trailing dot.
 */
function clean(raw: string): string {
  return (raw || '')
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, '')
    .replace(/\/.*$/, '')
    .replace(/\.$/, '');
}

/**
 * Analyze a typed hostname into its parts (registrable domain, subdomain,
 * public suffix) with a validity verdict. Pure heuristic — see the note on
 * MULTI_PART_SUFFIXES regarding server authority.
 */
export function analyzeDomain(raw: string): DomainAnalysis {
  const full = clean(raw);

  if (full === '') {
    return {
      empty: true,
      valid: false,
      apex: false,
      registrable: '',
      subdomain: '',
      full: '',
      reason: null,
      tld: '',
    };
  }

  // Basic hostname shape: dot-separated labels of [a-z0-9-], not starting or
  // ending with a hyphen, with at least two labels.
  const okChars = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;
  if (!okChars.test(full)) {
    return {
      empty: false,
      valid: false,
      apex: false,
      registrable: '',
      subdomain: '',
      full,
      reason: 'malformed',
      tld: '',
    };
  }

  const labels = full.split('.');
  const last = labels[labels.length - 1];
  const listed = /^[a-z]{2,}$/.test(last); // TLD label must be alphabetic, length >= 2

  const last2 = labels.slice(-2).join('.');
  const nTld = MULTI_PART_SUFFIXES.has(last2) ? 2 : 1;
  const tld = labels.slice(-nTld).join('.');

  if (!listed || labels.length <= nTld) {
    return {
      empty: false,
      valid: false,
      apex: false,
      registrable: '',
      subdomain: '',
      full,
      reason: 'suffix',
      tld,
    };
  }

  const registrable = labels.slice(-(nTld + 1)).join('.');
  const subRaw =
    labels.length > nTld + 1 ? labels.slice(0, labels.length - nTld - 1).join('.') : '';
  const apex = subRaw === '' || subRaw === 'www';

  return {
    empty: false,
    valid: true,
    apex,
    registrable,
    subdomain: apex ? '' : subRaw,
    full,
    reason: null,
    tld,
  };
}
