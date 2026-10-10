.. A new scriv changelog fragment.

Documentation
-------------

- Added an operator runbook for checking, with approval, which claims a
  Microsoft Entra tenant's ID tokens carry for each account type, recording
  only sanitized claim presence and type. A new test drives the real Entra
  strategy and route with synthetic tokens: a token without an ``email``
  claim is refused as ``missing_email`` and no other claim or lookup stands
  in for it. A missing email claim is reported as exactly that, not as a
  missing mailbox. (#3499)
