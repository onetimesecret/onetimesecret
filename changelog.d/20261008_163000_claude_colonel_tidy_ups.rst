.. A new scriv changelog fragment.

Changed
-------

- The email-delivery test from the colonel console and ``bin/ots email test``
  is now written for the person who receives it, usually a customer reporting
  missing emails. It says what the message is, that no action is needed, and
  how to keep other emails out of spam. The mail provider and the sending
  host's machine name no longer appear in the message; the console and the
  CLI still show them to the operator.
- Feedback emails from signed-in users list the user's organizations by
  public id, and link the user and each organization to its colonel page.
- In the colonel console, each domain on an organization's page links to that
  domain's page.
- The colonel console links customers, organizations, and domains by their
  public ids only. The customers list and the domain page's owner link used
  internal ids, which then appeared in browser history and server logs.

Fixed
-----

- The account diagnostics panel on a colonel customer page could time out on
  a large database. The per-IP login lockout check scanned the whole keyspace
  in small batches; it now uses larger batches and stops after 5 seconds, and
  the panel says when that check is incomplete.
