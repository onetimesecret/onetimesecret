.. A new scriv changelog fragment.

Fixed
-----

- Schema validation failures now name the field that failed. ``gracefulParse``
  builds its log message from ``error.issues`` (field path + issue code) and
  promotes the failing paths to a searchable Sentry tag (``schemaField``),
  instead of logging a generic "Schema validation failed" string with the
  precise path buried in non-searchable extras. Only field paths and codes are
  recorded — never the offending values — so it is safe for secret payloads.
  This is the diagnostic prerequisite for #3424: three prior fixes shipped on
  inference because production discarded the failing field. (#3424)

Added
-----

- ``src/tests/contracts/issue-3424-failing-field-forensics.spec.ts``, an
  empirical contract gate that runs the real V3 response schemas against
  wire-faithful ``safe_dump``/logic-class payloads — including legacy-state,
  poisoned, and raw-merge fixtures the existing ``state:'new'`` tests never
  exercised — and pins the field-level failure matrix so a regression in the
  serialization shape or contract strictness fails CI with the field named.
  See ``docs/specs/issue-3424-root-cause-analysis.md``. (#3424)
