.. A new scriv changelog fragment.

Changed
-------

- Locale messages load on demand. English ships with the entry bundle and
  every other language is its own chunk, fetched before the app mounts or
  before a language switch takes effect. A page opened with ``?locale=bg``
  renders in Bulgarian from its first paint, and a switch never shows a
  half-translated page.
- A ``?locale=`` URL parameter now applies on signed-in pages too, as it
  already did on the server; the account language used to replace it. It
  is kept for the browser session and never saved to the account.
- ``<html lang>`` follows language switches and uses BCP 47 tags
  (``pt-BR``, not ``pt_BR``). The page title follows switches too.
- A language whose chunk fails to load does not block the page. On the
  first load the page opens in the installation's default language, or in
  English, with a notice that names the language that failed and links to
  the feedback form. A failed switch later keeps the current language and
  shows the same notice.

Fixed
-----

- Fallback chains configured with regional keys (``de-AT``, ``fr-CA``,
  ``pt-BR``) now apply in the browser, as they already did on the server.
