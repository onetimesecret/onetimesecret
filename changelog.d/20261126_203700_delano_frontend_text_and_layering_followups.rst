Changed
-------

- A session signed in with "Remember me" ticked now lasts 30 days, as the
  sign-in form says, instead of 14. This is also the default absolute session
  lifetime (``SESSION_ABSOLUTE_TIMEOUT``); a lower value there still ends a
  remembered session sooner.
- Secret lifetimes that are not a whole number of one unit are shown exactly,
  for example "1 hour 2 seconds" instead of "3602 seconds" and "25 hours"
  instead of "1500 minutes". The lifetime itself is unchanged.
- The incoming secrets form shows how long a secret lasts as a duration
  ("7 days") instead of a number of seconds.
- The recipients section of a domain's incoming secrets settings has a new
  description.

Fixed
-----

- A confirmation dialog opened from the members or domains table in the
  organization settings covers the whole page instead of only its card.
- An error banner on the homepage secret form no longer covers the account,
  organization, language or "create link" menus.
- On workspace pages, an open menu near the bottom of the page is no longer
  hidden behind the fixed footer.
- The header of a domain settings page can no longer be clicked while the
  page is loading or saving, and is no longer covered by the stale-session
  notice.
- The dashboard passphrase field now reports a passphrase that is too long or
  that misses a required character type, shows the character rule when one
  applies, marks a required passphrase left empty, and no longer calls a
  too-short passphrase "(Optional)".
- The "require a passphrase" setting in the organization sharing controls and
  in a domain's incoming secrets settings is shown as on and locked when the
  installation, or for a domain the organization, already requires one.
- The organization sharing controls now say that a blank maximum lifetime
  removes the organization's limit.
- Validation messages on the secret form, and three labels read by screen
  readers, can now be translated.

AI Assistance
-------------

- A coding agent made these changes from a review list and added unit tests.
  The Ruby specs for the "Remember me" change were not run by the agent.
