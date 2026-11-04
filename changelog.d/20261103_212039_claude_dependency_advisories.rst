.. A new scriv changelog fragment.

Security
--------

- Updated ``rack`` from 3.2.7 to 3.2.8 for GHSA-5v64-555j-wjxm (High),
  GHSA-2j8w-xcrc-x985 (Medium), GHSA-wvg4-6p58-3gh3 (Medium) and
  GHSA-p8x9-v4hv-2w4g (Low). (#4883)

- Updated ``sanitize`` from 7.0.0 to 7.0.1 for GHSA-wgw9-qhqg-8hv5. (#4874)

- Updated ``sqlite3``, used by the SQLite authentication database, from
  2.9.6 to 2.10.2 for GHSA-4fqr-96q8-xrfx (Medium). (#4886)

- Updated ``nokogiri`` from 1.19.4 to 1.19.7 for GHSA-4p39-36wj-23h4 (Low),
  GHSA-v995-44v6-5fqm (Low) and GHSA-3w22-6jfg-527w (no severity published),
  and ``loofah`` from 2.25.2 to 2.25.3 for GHSA-345x-3rq2-jfrm,
  GHSA-h6v6-rg66-fqj4, GHSA-m3x9-938q-5767 and GHSA-mf2j-8f84-cc9q (all
  Medium) and for GHSA-jcff-cj73-4w4f and GHSA-p9wj-w8xq-vjx6 (no severity
  published). (#4895)

- Added ``resolv`` 0.7.2 to the bundle for GHSA-x2vh-ff4w-v64c
  (CVE-2026-80212, CVSS 7.5: memory exhaustion from malicious DNS responses)
  and GHSA-jr95-x3fr-rcg4 (CVE-2026-80213, CVSS 4.0: hostname validation
  bypass). ``resolv`` is a default gem, so the app ran the 0.7.1 bundled
  with Ruby 3.4.10, which bundler-audit does not check. (#4910)

- Updated ``activesupport`` and ``activemodel`` from 8.1.3 to 8.1.4.1 for
  GHSA-8474-xrp6-wh69 (High, CVSS 7.5: denial of service in
  ``safe_constantize``) and GHSA-2w9f-fxwj-w2qf (Medium, CVSS 4.7: XSS in the
  MessagePack serializer). Both gems come in through
  ``omniauth_openid_connect``; application code does not call Active Support.
  (#PRNUM)

- Updated ``zod`` from 4.3.6 to 4.6.6 for GHSA-mrhx-c7xc-m3w5 (High).
  (#4854, #4887)

- Updated ``dompurify`` from 3.4.16 to 3.4.17 for GHSA-cg2g-xh64-v4q7
  (Critical), GHSA-mrv2-3pqr-j5jr (High) and GHSA-c6gr-qvv4-5v3f (Low).
  (#4853)

- Updated ``vue-i18n`` from 11.4.4 to 11.4.14 and ``@intlify/core`` from
  11.3.0 to 11.4.14 for GHSA-83rm-6c8r-g728 (High) and GHSA-8rc2-428q-7ww3
  (Low). (#4884, #4885)
