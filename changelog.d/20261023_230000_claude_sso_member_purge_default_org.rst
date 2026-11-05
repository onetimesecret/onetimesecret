.. A new scriv changelog fragment.

Fixed
-----

- Purging an account, and closing it from account settings, no longer
  refuses with ``default_workspace_mismatch`` a member who joined an
  organization through SSO on its custom domain. SSO sign-in makes that
  organization the member's default, and the purge treated it as a conflict.
  The purge now refuses only when the default names a second default
  workspace the account owns. (#4860)
- Removing a member from an organization clears their default organization
  when it names the organization they left. This applies to every removal
  path: the organization members page, ``bin/ots memberships remove``, the
  colonel API, custom-domain deletion and the membership repair jobs.
  Members removed before this release keep the old value, which
  ``bin/ots customers doctor --all --repair`` clears. It no longer blocks a
  purge. (#4860)
