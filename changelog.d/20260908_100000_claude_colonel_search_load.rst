.. A new scriv changelog fragment.

Fixed
-----

- Organization searches and filters no longer load every organization and
  owner, avoiding lengthy requests on large deployments.

- Admin-console searches now run only when submitted with Enter or the search
  button.

- Admin session lists and customer and domain searches now use fewer datastore
  requests, improving performance for large result sets.

Added
-----

- The admin console now shows the running app version, linked to its release
  notes, in the sidebar.
