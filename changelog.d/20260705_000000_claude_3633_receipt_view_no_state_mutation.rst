.. A new scriv changelog fragment.

Fixed
-----

- Viewing a secret's receipt/metadata page no longer mutates the secret's
  lifecycle state. The receipt-page GET previously flipped the receipt to
  ``previewed`` as a side effect, conflating "the creator looked at their
  own receipt" with "the secret link was opened". Loading the receipt page
  now records a one-time ``receipt_viewed`` audit event (bounded per receipt
  by a new ``receipt_viewed_at`` observability field, so a bookmarked or
  monitored receipt page cannot flood the org's capped audit trail);
  ``previewed`` is reserved for the distinct, auditable event of the creator
  opening their own secret *link* (recorded on the access timeline). This
  completes the #3633 GET-safety work, which had left the receipt-page
  transition (and the legacy v1 GET transitions) in place. (#3633)

- A generated secret's plaintext is now shown to its creator on the receipt
  page *exactly once* ("one time"). Retiring the ``previewed`` state mutation
  had left the value re-displayable on every reload within the display window
  (v2) or unbounded (v1). Both paths now claim the display atomically via a
  new ``secret_value_shown_at`` field (Redis ``HSETNX``), so a repeated or
  concurrent load never re-reveals the value. The claim is taken at display
  time: an at-most-once semantic, matching the old state gate — a lost
  response forfeits the reveal rather than risking a second one. The display
  window (``generated_value_display_ttl``) now bounds only *when* the single
  reveal may occur, not how many times. (#3633)

- The one-time ``receipt_viewed`` audit event is now claimed atomically as
  well, so simultaneous first-loads of a receipt record exactly one event
  instead of racing to record two. (#3633)

Changed
-------

- ``previewed`` is retired as a receipt lifecycle *state*: no request path
  advances a receipt to ``previewed`` anymore. New receipts move
  ``new -> revealed/burned/expired/orphaned`` only. The creator's own
  secret-link open is now surfaced from the append-only access timeline
  (``view_count`` / ``first_access``) rather than a mutated state field,
  and is recorded in the org audit trail as ``previewed`` (was
  ``creator_secret_get``). Read-side ``state?(:previewed)`` checks and the
  ``previewed`` field are retained for backward compatibility with data
  written before this change. (#3633)

- The ``is_previewed`` receipt attribute now means "the secret link has been
  accessed at least once" (derived from the access timeline), not "state ==
  previewed". This keeps every consumer working after the state was retired:
  the receipt page's post-creation banner and the recent-secrets dashboard
  status now key off telemetry instead of a mutated field, with no
  client-side change. Legacy receipts still in a ``previewed``/``viewed``
  state continue to report ``true``. (#3633)

- The legacy v1 secret and receipt read endpoints (and the v1
  ``generate``/``show_receipt`` controllers) no longer advance state on a
  GET, matching v2. Downstream guards (``viewable?``, ``burned!``,
  ``win_reveal_claim!``) already accept ``new``, so no behavior depends on
  the removed transitions. (#3633)
