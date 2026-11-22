.. A new scriv changelog fragment.

Fixed
-----

- The V1 API's receipt, secret and burn responses build their links on the
  secret's custom share domain when custom domains are on
  (``features.domains.enabled``). V1 read the setting from
  ``site.domains.enabled``, where it lived through v0.20, so these links
  used the main host, unlike the link in V1's create response. (#3991)

Changed
-------

- The colonel system settings endpoint (``GET /api/colonel/config``) no
  longer returns a ``logging`` section, which was always empty, or a
  ``billing`` section, which it never returned. Logging and billing config
  are not part of the main config file. (#3991)
