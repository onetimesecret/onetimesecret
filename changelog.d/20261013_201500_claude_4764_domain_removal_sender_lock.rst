.. A new scriv changelog fragment.

Fixed
-----

- Removing a custom domain and provisioning its email sender domain no
  longer run at the same time. A removal while provisioning is running
  returns a ``conflict`` error and leaves the domain in place, and
  provisioning while a removal is running fails. Provisioning that starts
  after the sender configuration or its domain was deleted now fails
  without registering the sender domain at the mail provider. Before, a
  provisioning that overlapped a removal could leave the sender domain
  registered at the provider with nothing pointing to it. This covers
  domain removal from the dashboard, the colonel endpoint and
  ``bin/ots domains remove``. (#4764)
