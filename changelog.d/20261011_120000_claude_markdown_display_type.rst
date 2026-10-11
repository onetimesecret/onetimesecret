Added
-----

- Secrets can be written in Markdown. A **Markdown** toggle on the create form
  (homepage and workspace) turns the textarea into a hybrid editor with a live
  preview beneath it; the recipient sees the secret rendered, with syntax
  highlighting for fenced code blocks, and can switch to the raw source. The
  toggle position is remembered in the browser like the expiration time. The
  choice is stored on the secret as ``display_type`` (``text`` or
  ``markdown``), accepted by the conceal endpoints and returned in the secret
  record; unknown values are rejected at creation, and generated passwords are
  always plain text. Rendered output is sanitized in the recipient's browser:
  images and other remote-loading elements are stripped, and links are shown
  as plain text with their destination rather than as clickable links.
