.. A new scriv changelog fragment.

Added
-----

- ``jobs.domain_refresh.dns_propagation_window`` (default ``24h``). Custom
  domains created within this window that are not yet verified or not yet
  resolving fill any room the regular page leaves under ``batch_size`` on each
  domain refresh run, so a new domain can be re-checked before a full walk of
  the domain set completes. Set it to ``'0'`` to disable.

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
  Re-verify in the Colonel domain toolbox now reports the outcome of the
  check, as the domain list and detail pages do, instead of announcing every
  completed call as a success.

Fixed
-----

- Under the ``approximated`` strategy, correctly configured custom domains no
  longer lose verified status when Approximated's DNS checker fails. The
  checker answers ``actual_values: false`` when its own lookup failed; that
  was read as a TXT mismatch and demoted the domain on the next verify or
  refresh run, which in turn disabled domain sign-in and SSO for it. Such an
  answer is now treated as indeterminate: the stored verified flag is left
  alone within the confirmation window, and the application tries its own
  TXT lookup. See ``lib/onetime/domain_validation/README.md`` for fallback
  behavior and the confirmation window.

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
