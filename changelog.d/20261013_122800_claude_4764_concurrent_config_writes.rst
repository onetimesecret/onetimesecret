.. A new scriv changelog fragment.

Fixed
-----

- Two edits to the same custom domain configuration (SSO, signup, sign-in,
  email sender, homepage, API or incoming secrets) no longer undo each
  other. An update now re-reads the stored configuration just before it
  writes, so fields it does not change keep the other edit's values,
  including the email verification state that background jobs record. An
  update that keeps losing to other edits, or whose configuration was
  deleted or created by another request in the meantime, returns a
  ``conflict`` error and changes nothing. (#4764)
- The audit log entries for these configurations now describe the
  configuration each change actually replaced or deleted, and the enabled
  and disabled entries compare against it, so concurrent edits no longer
  produce a wrong previous value or a missing or extra entry. (#4764)
- A PATCH to a domain's SSO configuration is checked against the stored
  configuration it changes, so it can no longer re-enable SSO that another
  request has just disabled. A sign-in configuration update can no longer
  keep the ``webauthn`` restriction after another request has removed it.
  (#4764)
- Background checks for an email sender domain now record their results
  only while the configuration still sends from the address they checked.
  A DNS or provider check that finishes after the sender address changed,
  or after the configuration was deleted, is discarded instead of being
  recorded against the new address or bringing the deleted configuration
  back. Sender domain provisioning that finishes in the same situation
  fails and stores nothing. When Verify Now cannot queue its checks, it no
  longer restores values from before its own reset or recreates a deleted
  configuration. (#4764)
- Deleting a domain's email sender configuration and provisioning its
  sender domain no longer run at the same time. A delete during
  provisioning returns a ``conflict`` error. Provisioning while a delete is
  removing the sender domain at the mail provider fails, so a configuration
  saved in that window has no DNS records until it is provisioned again.
  Before, a provisioning that overlapped a delete could leave the sender
  domain registered at the provider with no configuration. (#4764)
