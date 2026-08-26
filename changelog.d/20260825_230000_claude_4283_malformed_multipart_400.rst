.. A new scriv changelog fragment.

Fixed
-----

- Malformed ``multipart/form-data`` requests now receive a ``400 Bad
  Request`` with an explanatory JSON message instead of failing deep in the
  middleware stack (#4283). Previously an empty or truncated multipart body
  raised a 500 from the first middleware that read request params, and a
  multipart Content-Type without a boundary parameter silently produced no
  form fields — surfacing on ``POST /share`` as a misleading "You did not
  provide anything to share". Well-formed multipart requests are unaffected;
  their body is now parsed once, up front, and memoized for the rest of the
  request.

AI Assistance
-------------

- AI assistance was used to trace the Sentry error signatures to the
  middleware-level multipart parse, implement the guard middleware, and add
  regression coverage.
