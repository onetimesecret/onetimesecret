Security
--------

- Responses served by a router's default "not found" or "server error"
  fallback (a request to an API path that has no route, for example) no
  longer carry ``Set-Cookie`` headers belonging to earlier requests. The
  fallback responses were built once per process and reused, and the
  session layer wrote each request's cookie into that shared response, so
  a later fallback response replayed every session cookie committed on a
  fallback since the worker started. A per-request copy of the response
  headers is now made directly around every router, so each response
  carries only its own cookie. Sessions whose cookies were exposed this
  way are already bound to the 24-hour inactivity deadline enforced in
  this release.
