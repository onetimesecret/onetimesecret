.. A new scriv changelog fragment.

Fixed
-----

- Schema validation failures now name the field that failed — in the log message
  and a searchable ``schemaField`` Sentry tag (paths and codes only, never
  values) — instead of a generic "Schema validation failed". (#3424)
