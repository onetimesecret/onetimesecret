.. A new scriv changelog fragment.

Security
--------

- Simple-mode sign-in now authenticates only the account named in the login
  field, including on requests that already carry a session.

Fixed
-----

- Simple-mode ``Login failed`` events now identify the attempted account rather
  than the account associated with the request session (#4361).
