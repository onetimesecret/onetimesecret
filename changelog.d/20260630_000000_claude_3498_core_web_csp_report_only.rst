.. A new scriv changelog fragment.

Security
--------

- The Core web app now emits an opt-in, report-only, nonce-based Content-Security-Policy on its HTML responses. Previously the ``site.security.csp.enabled`` / ``CSP_ENABLED`` flag only protected the V1 API surface; the user-facing HTML pages — where inline scripts actually run — emitted no CSP at all, which made the per-request nonce inert and provided zero XSS protection. When ``site.security.csp.enabled == true``, HTML responses now carry a ``Content-Security-Policy-Report-Only`` header built from the same hardened, nonce-only policy the API enforces (shared via ``Onetime::Security::Csp``). Report-only is the deliberate first rollout step; promotion to an enforcing header is a planned follow-up. The flag default remains ``false``. (#3498)
