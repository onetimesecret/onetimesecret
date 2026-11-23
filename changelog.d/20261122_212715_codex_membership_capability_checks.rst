Changed
-------

- Organization invitations and management actions now use the acting member's
  permissions even when the billing plan omits those permissions. API clients
  receive HTTP 403 with ``CapabilityRequired`` when a permission is missing.
  (#3491)
