.. A new scriv changelog fragment.

Fixed
-----

- Organization deletion now detects custom-domain drift before teardown and
  refuses deletion until attached domains are removed. Repair unrecoverable
  drift with ``bin/ots domains doctor --all --repair``.

AI Assistance
-------------

- Claude assisted with organization-deletion drift handling and coverage.
