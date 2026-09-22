.. A new scriv changelog fragment.

Fixed
-----

- Opening ``/recent`` directly showed an empty list: the receipt list only
  loaded if the dashboard had been visited first, and the dashboard's
  5-minute status refresh never sent a request. Both now load and refresh.
- After signing out or switching accounts in the same tab, the custom-domain
  list could stay empty until a forced refresh.
- The browser console no longer logs "API instance provided in options,
  ignoring." once per store at start-up.
