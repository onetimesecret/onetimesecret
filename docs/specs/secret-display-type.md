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

```ruby
# lib/onetime/models/secret.rb
field :display_type        # one of DISPLAY_TYPES; nil reads as DEFAULT_DISPLAY_TYPE

DISPLAY_TYPES        = %w[text markdown].freeze
DEFAULT_DISPLAY_TYPE = 'text'
```

- Stored on the **Secret** (the thing that is displayed), not the Receipt.
- Stamped once in `Receipt.spawn_pair(..., display_type:)` from the conceal
  request. Never inferred from the content.
- Read through `Secret#display_type_or_default`: an unset field (every record
  created before the field existed) and a value this build does not know (a
  downgrade after a newer type shipped) both read as `text`. `safe_dump` emits
  the normalized value, so the client never sees nil.

Why a flat field and not a nested `config` key: there is one setting. A plain
field on the existing hash costs no extra Redis key, no separate TTL, and no
extra round trip. A grouping key can be introduced when a second setting
arrives; the field name and value space would not change.

## 2. The request

`display_type` is an optional member of the conceal payload, beside `ttl`,
`passphrase` and `share_domain`:

```json
{ "secret": { "secret": "# Hello", "display_type": "markdown" } }
```

`V2::Logic::Secrets::BaseSecretAction` (V3 inherits it):

- `process_display_type`: absent or blank → `text`; otherwise stripped and
  downcased. A non-scalar shape (`secret[display_type][]=`) is a payload error,
  like `ttl`.
- `validate_display_type`: a value outside `DISPLAY_TYPES` is a `FormError`
  (`field: display_type`, `error_type: invalid`). Fail at creation, where the
  creator can correct it, rather than fall back silently at reveal.
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

**Create forms** (`SecretForm`, `WorkspaceSecretForm`): a Markdown toggle above
the textarea. When on, the textarea stays the single place the text is edited
and a sanitized live preview renders beneath it. The toggle position is
remembered in `localStorage` via `localReceiptStore.preferredDisplayType`, the
same mechanism and lifetime as the remembered TTL.

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
  `style`, `svg` and `math` are stripped; `style` and `data-*` attributes are
  dropped; URI attributes that remain are limited to `https`, `http` and
  `mailto`.
- If rendering throws, the component shows the source as plain text. The
  recipient must never lose the value to a rendering bug.

## 4. Extending the value space

Add the value to `Secret::DISPLAY_TYPES` and to `secretDisplayTypeValues`, then
teach the reveal components what the type means. Clients that predate the value
fall back to `text` on read; servers that predate it reject it at creation.

Example of the kind of type this is meant to grow into — `httplink`: the value
is a URL, and instead of rendering it the reveal page shows a "you are about to
open an external link" interstitial naming the host before the recipient
proceeds. Nothing about storage, the request, or the receipt would change; only
the reveal components learn a new case.
