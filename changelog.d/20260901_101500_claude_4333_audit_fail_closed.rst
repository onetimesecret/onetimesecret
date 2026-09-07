.. A new scriv changelog fragment.

Security
--------

- Destructive operator actions now report an audit-write failure instead of a
  successful response when their audit event cannot be stored (#4333).
  Because most actions write their audit event after the mutation, operators
  must reconcile the target after such a failure; it may have completed.
