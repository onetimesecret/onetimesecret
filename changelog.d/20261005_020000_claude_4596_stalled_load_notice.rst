Fixed
-----

- When the app bundle never starts (an edge rewrite such as Cloudflare Rocket
  Loader, or a failed bundle fetch), the page no longer spins indefinitely.
  After 30 seconds the server-rendered shell says the page is taking longer
  than expected to load, offers a reload, points to the recipient's usual
  support contact or the sender, and shows the request id as a reference. The
  reveal is a CSS timer, so it works when no script runs. (#4596)
