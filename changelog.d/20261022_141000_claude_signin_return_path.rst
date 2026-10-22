.. A new scriv changelog fragment.

Fixed
-----

- A signed-out visit to a page that needs a session (``/recent``,
  ``/dashboard``, ``/account`` and the rest) redirects to
  ``/signin?redirect=<page>`` instead of a bare ``/signin``, so signing in
  returns the visitor to the page they asked for. The link in the
  expiration-warning email depends on this. Only a same-origin path is
  carried, validated on the server and again by the app before it
  navigates; a POST is never used as a return path.
