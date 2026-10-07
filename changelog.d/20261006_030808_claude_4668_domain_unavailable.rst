.. A new scriv changelog fragment.

Changed
-------

- A custom domain whose record cannot be read now gets one answer on
  every authentication route: a 503 saying the domain is not available
  and, if it is yours, to contact us. Starting single sign-on on such a
  domain lands on the sign-in page with the same message. The reply used
  to depend on which error the read raised. The refusal stays fail-closed:
  no email, no identity provider redirect, reset keys untouched (#4668).
