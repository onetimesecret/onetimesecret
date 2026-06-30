.. A new scriv changelog fragment.

Fixed
-----

- The custom-sender API no longer rejects a blank ``from_address`` with "From
  address is required"; it now defaults to ``noreply@<domain>`` first, so an
  operator can enable the sender without hand-typing an address, matching the
  frontend default.
