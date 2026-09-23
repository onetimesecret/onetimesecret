.. A new scriv changelog fragment.

Changed
-------

- Colonel now rejects malformed related passkey origins and origins owned by
  another organization with a field-specific validation error. Enter complete
  origins such as ``https://host``, not bare domains. #4421

Fixed
-----

- The first save of a domain's sign-in configuration now retains its related
  passkey origins. #4421
