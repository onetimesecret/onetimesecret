.. A new scriv changelog fragment.

Security
--------

- Semantic Logger output (every appender, including the optional
  ColonelAudit syslog destination) now has the userinfo and the whole query
  string of each URI replaced with ``***`` in these parts of a log event:
  the message, tags and named tags, the messages of the logged exception
  and its causes, and, inside Hash, Array and Set payloads, String, Symbol,
  URI and Exception values and String, Symbol and URI keys. This includes
  harmless queries, so a logged ``?page=2`` now reads ``?***``. Email
  addresses are unchanged. Values that cannot be scrubbed within fixed
  limits are replaced with a ``[log scrub: ...]`` placeholder, as is text
  in an encoding that cannot be converted to UTF-8 (UTF-7, ISO-2022-JP-2)
  when its bytes contain a ``:``; such text without a ``:`` is left as it
  is. An event whose scrubbing fails is logged as
  ``[log scrub failed: event withheld]``. Not covered:

  - other objects in a payload, in tags or named tags, or as the message,
    rendered through ``inspect`` or ``to_s``
  - a ``://`` split by a terminal escape other than an SGR color code or a
    bare ESC (for example ``\e[K`` or an OSC sequence), by a zero-width
    character, or by a backspace
  - Exception payload values whose class defines its own ``to_json`` or
    ``as_json`` (JSON output)
  - exception and cause backtraces (their messages are scrubbed)
  - thread names, and the metric, dimensions and context fields
  - on Semantic Logger 4.x, the logger name, thread name or context set by
    a logging block that returns a Hash
  - values the caller changes after the log call, before the background
    writer formats them
  - output written directly with ``warn`` or to stdout/stderr, and Sentry
    reports
