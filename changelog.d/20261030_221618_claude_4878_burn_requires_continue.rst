.. A new scriv changelog fragment.

Changed
-------

- A v2 or v3 burn request without ``"continue": true`` now fails with a 422
  error on the ``continue`` field instead of answering 200 with a "Secret
  burned" title while leaving the secret intact. Clients that burn through the
  API must send ``"continue": true``, as the web app already does. A request
  without it gets the same error whether or not its passphrase is correct, and
  does not count toward the passphrase attempt limit. (#4878)
