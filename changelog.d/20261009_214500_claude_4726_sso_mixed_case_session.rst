.. A new scriv changelog fragment.

Fixed
-----

- A first SSO sign-in whose identity provider sent an email address with
  capital letters (for example a Microsoft Entra guest address containing
  ``#EXT#``) created the account but did not sign the user in. SSO now
  stores the address in lowercase, as password sign-up already does, and
  sign-in finds the account's customer record through its stored link
  before falling back to the lowercase address. An address that lowercasing
  cannot represent faithfully (one containing ``ß``, for example) is refused
  as invalid rather than stored under a different spelling (#4726).
