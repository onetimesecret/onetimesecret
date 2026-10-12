.. A new scriv changelog fragment.

Changed
-------

- Colonel step-up (POST /api/colonel/elevation) now moves the session to a
  new session id before it opens the elevated window, in both
  authentication modes. The operator stays signed in, and the session
  that existed before the step-up is ended the way a sign-out ends it. If
  the old session cannot be ended, no window is opened and the console
  shows a message asking to try again; the attempt is recorded as a failed
  step-up. The admin console picks up the new session after a step-up
  without a page reload (#4466).
