Added
-----

- Secrets can be written in Markdown. On the homepage, a **Format with
  Markdown** switch below the textarea adds a live preview beneath it; on the
  workspace dashboard, a **Markdown** chip next to the privacy options does the
  same, with the preview beside the textarea on wide screens. The recipient
  sees the secret rendered, with syntax highlighting for fenced code blocks,
  and can switch to the raw source. The dashboard remembers the choice in the
  browser like the expiration time; the homepage starts from plain text. The
  choice is stored on the secret as ``display_type`` (``text`` or
  ``markdown``), accepted by the conceal endpoints and returned in the secret
  record; unknown values are rejected at creation, and generated passwords are
  always plain text. Rendered output is sanitized in the recipient's browser:
  images and other remote-loading elements are stripped, and links are shown
  as plain text with their destination rather than as clickable links.
