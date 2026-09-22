.. A new scriv changelog fragment.

Removed
-------

- Frontend code nothing could reach: the two ``src/views/incoming`` views
  (duplicates of the live ``apps/secret/conceal`` components), the
  dashboard's hidden refresh button and its never-set toasts, the secret
  links table's "message deleted" toast that no row could trigger, and the
  ``web.secrets.messageDeleted`` locale key in every locale. No route, import
  or translation is affected.
