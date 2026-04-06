.. A new scriv changelog fragment.

Changed
-------

- Invitation login flow now accepts the invite atomically during login instead of requiring a separate API call afterward. Reduces latency and prevents race conditions where login succeeds but invite acceptance fails. (#2897)
