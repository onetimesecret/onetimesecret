.. A new scriv changelog fragment.

Added
-----

- ``jobs.domain_refresh.dns_propagation_window`` (default ``24h``). A custom
  domain that is not yet verified or not yet resolving is re-checked on every
  domain refresh run for this long after it was created, in addition to the
  regular page, so a new domain does not wait a full walk of the domain set
  for DNS to propagate. Set it to ``'0'`` to disable.

Changed
-------

- The domain refresh job now walks the whole set of custom domains, one page
  of ``batch_size`` per run, instead of refreshing the newest ``batch_size``
  domains on every run. The page is derived from the clock and
  ``check_interval``, so nothing is stored between runs. On installs with
  more domains than ``batch_size``, every domain is now refreshed once per
  walk (number of pages times ``check_interval``); a skipped run costs its
  page one extra walk.

- Verify results distinguish "could not tell" from "no". The Colonel verify
  response gains ``details.dns_indeterminate``, ``details.dns_message`` and
  ``details.dns_outcome`` (``validated``, ``indeterminate``,
  ``override_held`` or ``failed``); the ``domain.verify`` audit event detail
  carries the same fields. ``bin/ots domains verify`` prints
  ``indeterminate`` and ``no (override)`` in place of yes/no, adds
  ``Indeterminate`` and ``Demoted`` counts to the bulk summary
  (``indeterminate_count`` and ``demoted_count`` in JSON, plus
  ``issue_details.dns_indeterminate``), and the domain refresh summary line
  and a warning log line report both, so a domain that lost verified status
  can be found without a console session.

Fixed
-----

- Under the ``approximated`` strategy, correctly configured custom domains no
  longer lose verified status when Approximated's DNS checker fails. The
  checker answers ``actual_values: false`` when its own lookup failed; that
  was read as a TXT mismatch and demoted the domain on the next verify or
  refresh run, which in turn disabled domain sign-in and SSO for it. Such an
  answer is now treated as indeterminate: the stored verified flag is left
  alone, and the application tries its own TXT lookup. The strategy also asks
  Approximated about a name that cannot exist, to record whether its checker
  tells a missing record apart from a failed lookup; the result is logged
  with the indeterminate outcome and does not change it.

- The same applies to resolving status. An Approximated vhost status of
  ``UNKNOWN`` no longer flips a domain's stored ``resolving`` flag to false,
  and ``ACTIVE_SSL_PROXIED`` (a host fronted by another proxy, such as a
  Cloudflare CNAME setup) now counts as ready like ``ACTIVE_SSL``.

- A verification override set in the Colonel admin now survives later
  checks. Previously the next verify or refresh run demoted the domain again
  when its TXT check failed, undoing the operator's decision without notice.
  The override is recorded on the domain (``verified_by_override``) and holds
  verified through failed checks until an operator removes it or a TXT check
  passes, at which point DNS holds the flag and the marker is cleared. The
  outcome is reported as ``override_held``.

- Domains beyond the newest ``batch_size`` were never refreshed by the domain
  refresh job, so their resolving and SSL status on the domain pages stayed
  at whatever was last stored. See the change to the job above.
