.. A new scriv changelog fragment.

Security
--------

- The custom-domain DNS setup widget no longer inserts provider instructions
  from the remote DNS service as raw HTML. Remote markup is sanitized first:
  scripts, inline event handlers, styles, forms and ``name`` attributes are
  removed; links keep only https, mailto and relative targets; images lose
  their source, as does any other attribute that would fetch a URL when the
  page renders, since the Content Security Policy only allows same-origin
  images; and attributes that act on other page elements by id, such as
  ``for`` and ``popovertarget``, are removed. Values from the service are
  escaped, and the widget's buttons use event listeners instead of inline
  ``onclick`` handlers: a remote handler that makes one of the widget's own
  known calls is mapped to the matching listener, and any other handler is
  dropped. If the sanitizer is unavailable or unsupported, the widget shows
  the instructions as plain text. (RISK-2026-08-14-M09)

Fixed
-----

- Leaving the custom-domain DNS setup page no longer leaves the widget's
  token renewal and document listeners running, and a response that arrives
  after the page is gone is ignored instead of throwing.
