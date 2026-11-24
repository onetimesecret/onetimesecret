Changed
-------

- Organization and account permission responses now distinguish subscription
  features from member capabilities. Incoming settings use the permission
  for the selected domain in billing and standalone installations. (#3491)

- Operators can compare an installation's existing grants with the new
  feature and capability fields using ``bin/ots migrations backfill-capabilities``.
  The command previews changes by default. (#3491)
