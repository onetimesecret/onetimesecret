.. A new scriv changelog fragment.

Fixed
-----

- The burn endpoints (v1 and v2) now honour ``continue=false``. Both parsed
  the flag into a proper boolean in ``process_params`` but then computed
  ``greenlighted`` from the raw ``params['continue']`` instead. Because every
  non-empty string is truthy in Ruby, a request carrying the string
  ``"false"`` (the common shape for form/query submissions) burned the secret
  anyway, destroying it against the caller's explicit intent. The greenlight
  check now uses the parsed ``continue`` boolean, so only a genuine truthy
  confirmation burns the secret.
