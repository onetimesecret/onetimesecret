.. A new scriv changelog fragment.

Fixed
-----

- A failing log sink during an OmniAuth callback that carries no Connect
  intent no longer turns an ordinary SSO sign-in into a refused Connect. The
  fail-closed handling now covers only the lookups made after a valid intent
  was found. #4431
