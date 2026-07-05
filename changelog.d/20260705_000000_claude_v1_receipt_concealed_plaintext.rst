.. A new scriv changelog fragment.

Changed
-------

- The V1 API receipt endpoint no longer reveals a concealed (user-supplied)
  secret's plaintext to the creator, aligning V1 with the V2/V3 behavior:
  only generated values are shown on the receipt, only on first view, and
  only within ``site.secret_options.generated_value_display_ttl`` of
  creation. Reading concealed plaintext back from the receipt sidestepped
  the at-most-once rule that V2/V3 deliberately enforce. Legacy
  integrations that depend on the old behavior can restore it with
  ``site.secret_options.v1_reveal_concealed_on_receipt: true`` (env:
  ``V1_REVEAL_CONCEALED_ON_RECEIPT=true``).
