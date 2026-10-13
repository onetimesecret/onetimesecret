# Secret display type: the `display_type` field

Status: **Implemented** (`text`, `markdown`) · Related:
`docs/specs/receipt-page-structure/receipt-source-field.md` (same shape of
change: a stored discriminator with a closed value space, stamped at creation)

A secret's value is opaque bytes to the backend and, until now, a read-only
`<textarea>` to the recipient. `display_type` is a presentation hint the creator
chooses when concealing: it tells the recipient's client how to show the value.
It says how to show, not what the value is, so it travels in the metadata
payload before reveal and is never a security control.

---

## 1. The field

The Secret enables a Familia feature that owns everything about the field:

```ruby
# lib/onetime/models/secret.rb
feature :display_type

# lib/onetime/models/secret/features/display_type.rb
TYPES   = %w[text markdown].freeze
DEFAULT = 'text'
base.field :display_type, fast_method: false
```

- Stored on the **Secret** (the thing that is displayed), not the Receipt.
- Stamped once in `Receipt.spawn_pair(..., display_type:)` from the conceal
  request. Never inferred from the content. The field has no fast writer
  (`display_type!`), so nothing rewrites it in place after creation.
- Class methods: `display_types`, `default_display_type`,
  `valid_display_type?`, and `normalize_display_type` (stripped, downcased,
  blank means `text`). Callers use these, not the feature's constants.
- Read through `Secret#display_type_or_default`: an unset field (every record
  created before the field existed) and a value this build does not know (a
  downgrade after a newer type shipped) both read as `text`, and the stored
  value is left alone. `safe_dump` emits the normalized value, so the client
  never sees nil. `display_type?(:markdown)` is the predicate.

Why a field on the Secret and not a related key: there is one immutable value
whose lifetime is exactly the secret's. On the Secret's own hash it costs no
extra Redis key or round trip, and it expires and is destroyed with the
record. A separate model (the `CustomDomain::SignupConfig` shape) would need
its own TTL kept in step with each secret and its own delete on reveal, burn
and colonel delete; TTL expiry runs no application code, so any drift would
leave orphaned keys.

## 2. The request

`display_type` is an optional member of the conceal payload, beside `ttl`,
`passphrase` and `share_domain`:

```json
{ "secret": { "secret": "# Hello", "display_type": "markdown" } }
```

`V2::Logic::Secrets::DisplayTypeParam`, included by `BaseSecretAction` (V3
inherits it), is the request-side counterpart of the feature:

- `process_display_type`: `Secret.normalize_display_type` (absent or blank →
  `text`; otherwise stripped and downcased). A non-scalar shape
  (`secret[display_type][]=`) is a payload error, like `ttl`.
- `validate_display_type`: a value outside `Secret.display_types` is a
  `FormError` (`field: display_type`, `error_type: invalid`). Fail at
  creation, where the creator can correct it, rather than fall back silently
  at reveal.
- `GenerateSecret` overrides `process_display_type` to `text`: a generated
  password is always plain text (Markdown would mangle `*`, `_`, `` ` ``).
- The V1 API is unchanged and always creates `text` secrets.

## 3. The client

Contract: `display_type: secretDisplayTypeSchema.catch('text')` on
`secretBaseCanonical` (`src/schemas/contracts/secret.ts`). Lenient on read for
the same reason the backend normalizes: a missing or unknown value must not
fail the whole record, which would show the recipient "no longer available" for
a secret nobody consumed (the #3424 failure shape). Strict on the request
payload (`secretDisplayTypeSchema.optional()`).

**Create forms**: the same `display_type` field, presented in each form's own
idiom. In both, the textarea stays the single place the text is edited and a
sanitized live preview (`MarkdownPreview`) shows what the recipient will see.

- Homepage (`SecretForm`): a labeled switch (`MarkdownModeSwitch`) with a
  visible one-line hint, under a collapsed **Advanced Options** disclosure
  below the passphrase and expiration fields. The disclosure keeps the
  familiar fields the whole form for a first-time visitor and leaves room for
  later options; while it is collapsed, Markdown mode shows as a chip beside
  the toggle. Hidden in generate-password mode, which sends no
  `display_type`. The preview (`SecretContentInputArea`) stacks below the
  textarea. Not remembered: the form starts from plain text on every load, as
  it does for the TTL, so a shared browser does not pass Markdown mode to the
  next visitor.
- Workspace dashboard (`WorkspaceSecretForm`): a chip (`MarkdownModeToggle`) in
  the `PrivacyOptionsBar` row, in its own right-aligned group (the bar's
  `trailing` slot), wired by `DashboardIndex` like the TTL. At `lg` and up the
  preview sits beside the textarea so the form keeps its height; below that it
  stacks. Remembered in `localStorage` via
  `localReceiptStore.preferredDisplayType`, the same mechanism and lifetime as
  the remembered TTL.

**Reveal** (`SecretMarkdownContent`, used by both `SecretDisplayCase`
variants): rendered Markdown by default with a Rendered / Source switch. The
copy button always copies the raw value.

### 3.1 Rendering and sanitization

`src/shared/utils/markdown.ts`. The renderer component imports it
dynamically, but the production build is a single chunk, so the parser and
highlighter ship in the main bundle either way:

- `marked` (GFM, line breaks on) parses; `highlight.js/lib/common` colors fenced
  code with a declared language. No auto-detection: a wrong guess colors prose.
- Links are not clickable. A Markdown link renders as its label followed by
  the real destination in parentheses, or the destination alone when the label
  already is it (GFM autolinks); raw `<a>` elements are unwrapped to their
  text. Rendered on this domain, a clickable link whose label says one thing
  and whose target is another would be a phishing aid. Following a link
  deliberately, behind a warning, is the kind of thing a separate display
  type should own (see `httplink` below).
- A dedicated `DOMPurify` instance sanitizes the HTML. On top of the HTML
  profile: `a` is forbidden; elements that load remote resources (`img`,
  `video`, `iframe`, `object`, …) are stripped, since a tracking pixel would
  tell the sender the recipient's IP and the moment of reveal; form controls,
  `style`, `svg` and `math` are stripped; `style`, `data-*`, `id` and
  `background` attributes are dropped; `class` keeps only the renderer's own
  tokens (`hljs*`, `language-*`, `md-link-url`), so sender HTML cannot use the
  app's utility classes to overlay the reveal page; URI attributes that remain
  are limited to `https`, `http` and `mailto`.
- If rendering throws, the component shows the source as plain text. The
  recipient must never lose the value to a rendering bug.

## 4. Extending the value space

The feature file's header lists the steps. In short:

1. Append the value to `TYPES` in
   `lib/onetime/models/secret/features/display_type.rb`. Servers that predate
   it reject it at creation; when one reads a stored value it does not know,
   it shows `text` and leaves the value as stored.
2. Put any rule about the content beside `validate_display_type` in the
   conceal logic, where the plaintext is still available.
3. Add the value to `secretDisplayTypeValues` and teach the reveal components
   what it means. Clients that predate it fall back to `text` on read.

The type this is meant to grow into is `httplink`: the value is a URL, and
instead of rendering it the reveal page shows a "you are about to open an
external link" interstitial naming the host before the recipient proceeds.
Storage, the receipt and the request shape stay as they are; the conceal logic
gains one content rule (the value must be a URL) and the reveal components
gain one case.
