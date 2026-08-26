.. A new scriv changelog fragment.

Fixed
-----

- The frontend locale schema now accepts any well-formed BCP 47 language
  tag (#4284). Previously it capped tags at 5 characters with an
  ``xx``/``xx-XX`` regex, rejecting legitimate values browsers actually
  send — ``en-US-POSIX``, ``zh-Hant-TW``, ``es-419`` — and capturing a
  Sentry error for each. Validation is now delegated to
  ``Intl.getCanonicalLocales`` with a 35-character bound, and a
  malformed visitor locale degrades silently to the supported-locale
  matching and the default locale instead of being reported as an
  application error.

AI Assistance
-------------

- AI assistance was used to trace the Sentry error signatures to the
  locale schema's length cap, widen validation to real BCP 47, and add
  regression coverage.
