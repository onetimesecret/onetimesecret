.. A new scriv changelog fragment.

Fixed
-----

- CI now extracts frontend build assets from the published image and uploads
  their source maps to Sentry, with preflight and post-upload delivery checks.

Added
-----

- ``SENTRY_FRONTEND_PROJECT`` is an optional repository secret for selecting
  the Sentry project that receives frontend source maps. Set it when that
  project is not ``frontend``; its value must also be included in
  ``SENTRY_PROJECTS``.
