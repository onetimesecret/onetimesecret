.. A new scriv changelog fragment.

Security
--------

- Rack now uses the proxy-configured forwarding header family when resolving
  request authority and scheme, preventing an unmanaged RFC 7239
  ``Forwarded`` header from overriding proxy-managed ``X-Forwarded-*`` values
  (#4377).

- Deployments whose edge sends only ``Forwarded`` must also send
  ``X-Forwarded-*`` headers for TLS scheme detection (#4377).
