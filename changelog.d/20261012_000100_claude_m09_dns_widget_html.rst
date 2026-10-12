.. A new scriv changelog fragment.

Security
--------

- The custom-domain DNS setup widget no longer inserts provider instructions
  from the remote DNS service as raw HTML. Remote markup is sanitized first
  (scripts, event handlers, styles, forms, and links other than https and
  mailto are removed); values from the service are escaped; and the widget's
  buttons use event listeners instead of inline ``onclick`` handlers. If the
  sanitizer is unavailable, the widget shows the instructions as plain text.
  (RISK-2026-08-14-M09)
