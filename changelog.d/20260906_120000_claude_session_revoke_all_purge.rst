.. A new scriv changelog fragment.

Added
-----

- Added ``ots sessions revoke-all <customer>`` for incident response. It
  revokes tracked customer sessions and Rodauth active-session records, and
  performs a capped best-effort sweep for legacy untracked sessions. A warning
  is shown if that sweep reaches its safety cap (#4354).

Changed
-------

- Customer purge now revokes tracked sessions and Rodauth active-session
  records first, with a capped best-effort sweep for legacy untracked sessions
  (#4352).

Removed
-------

- Removed the ineffective ``ots session clean`` command. Use
  ``ots sessions revoke-all`` or ``ots session delete`` instead (#4354).

- Removed the nonfunctional Colonel configuration editor write controls. The
  console configuration view is read-only (#4355).
