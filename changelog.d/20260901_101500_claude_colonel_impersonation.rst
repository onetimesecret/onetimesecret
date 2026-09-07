Added
-----

- Colonel now provides a confirmed, reason-required **Impersonate** action on
  the customer detail page. It creates a 30-minute, read-only customer view
  with a persistent banner and a **Stop impersonating** control.

- Impersonation blocks actions that could change data or create customer-facing
  artifacts, including secret, account, billing, and Colonel operations.

- Impersonation starts and normal in-process ends, including expiry, are
  recorded in the operator audit trail.
