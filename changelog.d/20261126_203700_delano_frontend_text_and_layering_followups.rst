Changed
-------

- A session signed in with "Remember me" ticked now lasts 30 days, as the
  sign-in form says, instead of 14. This is also the default absolute session
  lifetime (``SESSION_ABSOLUTE_TIMEOUT``); a lower value there still ends a
  remembered session sooner. Sessions signed in before this change keep their
  14-day deadline.
- Secret lifetimes that are not a whole number of days are shown exactly in
  hours, minutes and seconds, for example "1 hour, 2 seconds" instead of
  "3602 seconds" and "25 hours" instead of "1500 minutes". The parts are
  joined the way the current language writes a list. The lifetime itself is
  unchanged.
- The incoming secrets form shows how long a secret lasts as a duration
  ("7 days") instead of a number of seconds.
- The recipients section of a domain's incoming secrets settings has a new
  description.
- When a passphrase breaks more than one rule, the secret form now names the
  first one (required, then minimum length, maximum length, character types)
  instead of the last.

Fixed
-----

- The secret creation forms no longer describe the passphrase as optional when
  a sharing control or the instance requires one.
- On the dashboard, an error banner no longer covers an open expiration or
  passphrase menu.
- An error banner on the homepage secret form no longer covers the account,
  organization or language menus.
- A confirmation dialog opened from the members or domains table in the
  organization settings covers the whole page instead of only its card.
- The header of a domain settings page can no longer be clicked while the
  page is loading or saving, and is no longer covered by the stale-session
  notice.
- The dashboard passphrase chip and the mobile privacy sheet now apply the
  same passphrase rules as submitting the form (minimum and maximum length,
  character types, and required) and show the same message for a broken rule.
  They show the character rule when one applies, mark a required passphrase
  left empty, and no longer call a too-short passphrase "(Optional)".
- The "require a passphrase" setting in the organization sharing controls and
  in a domain's incoming secrets settings is shown as on and locked when the
  installation, or for a domain the organization, already requires one.
- The organization sharing controls now say that a blank maximum lifetime
  removes the organization's limit.
- Validation messages on the secret form, and three labels read by screen
  readers, can now be translated.
- Confirmation dialogs now all close the same way: Escape and a click on the
  dimmed background both cancel. Before, some closed only on Escape (removing
  one session, removing a member or domain) and others only on a background
  click (logging out all other sessions, disabling two-factor authentication,
  regenerating recovery codes), and account deletion closed on neither. While
  a request is running, neither closes a dialog that disables its Cancel
  button.

AI Assistance
-------------

- Coding agents made these changes from review lists, combined two sets of
  overlapping fixes into one, and added unit tests and the related Ruby specs
  for the "Remember me" change.
