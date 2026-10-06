Fixed
-----

- When the app bundle never starts (an edge rewrite such as Cloudflare Rocket
  Loader, or a failed bundle fetch), the page no longer spins indefinitely.
  After 30 seconds the server-rendered shell says the page is taking longer
  than expected to load, offers a reload, suggests contacting support or the
  sender, and shows the request id as a reference. The reveal is a CSS timer,
  so it works when no script runs. When the entry script fails to download
  (for example a stale chunk after a deploy) or runs but throws during
  startup, the same notice appears at once as a failure and the spinner
  stops. (#4596)
