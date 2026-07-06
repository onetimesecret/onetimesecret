# The receipt page as a set of secret kinds (structural rethink)

Status: **Proposed** · Prompted by: the incoming-secret share-link leak
(fixed separately — see "Motivating defect" below) · Related:
`docs/specs/recipient-disclosure/`, `docs/specs/secret-creation-flows/`

The receipt (metadata) page — `ShowReceipt.vue` and its `V2::Logic::Secrets::ShowReceipt`
backend — was designed when there was effectively **one** kind of secret: the
creator makes a link and holds it. Since then the product grew several kinds
with materially different display and capability needs, but the page never grew
a concept of "kind." Each new need was bolted on as another boolean. This
document proposes making the kind explicit and letting it drive one payload,
so display and capability stop drifting apart.

---

## 1. Motivating defect (why now)

Incoming secrets require that the _creator_ not see the secret link: on a custom
domain, the creator is an invited guest, and opening the link themselves would
spend the one view and break the site owner's workflow. The link was hidden in
`SecretLink.vue` (`v-if="!details.show_recipients"`) — but the backend still
shipped `share_url`, `share_path`, and `secret_identifier` in the JSON payload.
A guest with devtools, or a `POST /api/v3/guest/receipts` batch call, could read
the identifier and reconstruct the link.

The fix withholds those fields at the serializer and the logic layer, keyed on a
stored **`source`** field (`'incoming'` set at creation). The _shape_ of the bug
is the point: **display gating and capability gating lived in different files and
drifted.** That is a structural symptom, not a one-off.

A first attempt keyed the withholding on _recipients present?_ instead. That
over-triggered: it also stripped the link from ordinary secrets the owner chose
to email (§2, "Email-shared"), where the owner _is_ the link holder and must
keep it. Recipients-presence is a proxy that conflates two distinct flows;
provenance is the real axis, and it must be recorded at creation, not inferred.

---

## 2. The kinds that actually exist

Two independent axes have been conflated into a scatter of derived flags:

- **`kind`** (`conceal` | `generate`) — the concealment _mechanism_: did the user
  type the value, or did the server generate it? Already stored.
- **`source`** (`standard` | `incoming`) — the submission _provenance_: did the
  owner create this secret, or did a guest submit it through an Incoming form?
  **This is the field to add** (§4.1); it cannot be derived from `kind` (an
  incoming secret is a `conceal`) nor safely from `recipients` (see below).

The four user-visible kinds are the product of these axes plus whether the owner
emailed the link:

| Kind             | Distinguisher                                | Link holder           | Recipient shown | Value shown   |
| ---------------- | -------------------------------------------- | --------------------- | --------------- | ------------- |
| **Standard**     | `source=standard`, `conceal`, no recipients  | creator               | —               | no            |
| **Generated**    | `source=standard`, `generate`, no recipients | creator               | —               | briefly (TTL) |
| **Email-shared** | `source=standard`, recipients present        | **creator** (emailed) | obscured email  | no            |
| **Incoming**     | `source=incoming`                            | recipient (delivered) | display name    | no            |

The security-relevant axis is **"who holds the link"** (creator vs recipient),
and it is `source == 'incoming'` — _not_ recipients-presence. An email-shared
secret has recipients but the creator still holds the link (they chose to also
email it); withholding it there is a regression. Email-address hiding and
link-withholding are therefore _separate_ consequences: obscuring the recipient
follows from "recipients present," but withholding the link follows only from
`source == 'incoming'`. Collapsing both onto recipients-presence is what the
first fix got wrong.

---

## 3. Current structure and its cost

**Backend — three-and-a-half payload builders, none aware of "kind":**

- `V2::Logic::Secrets::ShowReceipt#_receipt_attributes` (v3 inherits it)
- `V1::Logic::Secrets::ShowReceipt#_receipt_attributes` (near-duplicate)
- `V2::Logic::Secrets::BurnSecret` (builds its own receipt hash)
- `V3::Logic::Secrets::ShowMultipleReceipts` (batch; `map(&:safe_dump)` only —
  bypasses the logic gates entirely, which is exactly why the leak reached an
  unauthenticated door)

**Backend — five overlapping display booleans** computed in a ~150-line
`process` method and partly duplicated in burn:
`show_secret`, `show_secret_link`, `show_receipt`, `show_receipt_link`,
`show_recipients`. Their interactions are subtle (e.g. `show_secret_link`
depends on state _and_ recipients; the frontend ignores it for the link block
and keys off `show_recipients` instead — a latent inconsistency the leak fix
had to route around).

**Frontend — one page, ad-hoc conditionals:** `ShowReceipt.vue` renders
`SecretLink`, the recipient section, `StatusBadge`, `TimelineDisplay`,
`BurnButtonForm`, `ReceiptFAQ`, each gated by a different combination of
`isAvailable`, `show_recipients`, `share_url`, `record.memo`. There is no single
place that says "this is an incoming receipt; render the incoming layout."

Cost: every new kind multiplies the boolean interactions; capability and display
gates are enforced in different files and drift (the leak); the batch endpoint is
a separate code path that silently skips the gates.

---

## 4. Proposal

### 4.1 Record provenance at creation, classify once on the model

Add a stored `Receipt#source` field (`'standard'` | `'incoming'`), stamped at
creation — `receipt.source = 'incoming'` in `CreateIncomingSecret`, `'standard'`
(or a `spawn_pair` default) everywhere else. Provenance is authoritative context
known at creation; it must be recorded then, not reconstructed at read time from
`recipients`.

On top of the stored `source` + existing `kind` + `recipients`, a derived
`Receipt#kind_profile` (value object) classifies a receipt into one of the kinds
in §2. Only the incoming/standard split needs the new stored field; the rest of
the classification stays a read-time derivation.

Legacy incoming receipts predating the field read as `standard` and revert to
link-shown. Given low incoming volume and short TTLs they age out on their own;
no backfill and no `recipients` fallback — the gate is the narrow, explicit
`source == 'incoming'`, which fails open on that small, self-expiring tail rather
than regressing email-shared secrets.

### 4.2 One capability map, keyed by kind

Replace the five ad-hoc booleans with a single declarative map from kind →
capabilities, e.g.:

```
CAPABILITIES = {
  standard:     { link_to_creator: true,  recipient: :none,     value: :never },
  generated:    { link_to_creator: true,  recipient: :none,     value: :ttl   },
  email_shared: { link_to_creator: true,  recipient: :obscured, value: :never },
  incoming:     { link_to_creator: false, recipient: :name,     value: :never },
}
```

Note `email_shared` keeps `link_to_creator: true` — the owner emailed the link
but still holds it — while obscuring the recipient. Only `incoming` withholds the
link. This is the split the recipients-proxy could not express.

State (new / previewed / revealed / burned / expired) composes _on top_ as an
availability gate, not as a separate parallel truth. `link_to_creator` is the
single source for withholding `share_url`/`share_path`/`secret_identifier`,
promoted from an inline predicate to a named property derived from the stored
`source` field (`link_to_creator == (source != 'incoming')`).

### 4.3 One payload composition, all consumers

`ShowReceipt`, `BurnSecret`, and `ShowMultipleReceipts` compose their payloads
from the same kind-aware builder. The batch endpoint stops being a gate-bypassing
special case. v1 either shares the builder or is frozen and delegated.

### 4.4 Frontend: a variant per kind, not a boolean per feature

`ShowReceipt.vue` resolves the kind once and renders a per-kind layout
(`StandardReceipt`, `IncomingReceipt`, …) over shared primitives
(`StatusBadge`, `TimelineDisplay`, `BurnButtonForm`). Display follows the
server capability map — the link block renders iff the server sent a link, which
is already the direction the leak fix moved `SecretLink.vue`.

---

## 5. Invariants this preserves (tie to recipient-disclosure)

The `recipient-disclosure` spec models what an anonymous/recipient observer may
learn. This rethink is the **owner/creator-surface** companion: it makes explicit
that the creator of an incoming secret is _not_ the full-disclosure `Π_owner`
principal the receipt page historically assumed, but a guest whose view is gated.
The capability map is where that distinction becomes checkable rather than
implied. Any kind added later declares its capabilities in one place, and CI can
assert that `link_to_creator: false` kinds never emit a link field.

---

## 6. Sequencing (incremental, no big-bang)

1. Add the stored `source` field, stamp `'incoming'` at creation, and withhold
   `share_url`/`share_path`/`secret_identifier` at the serializer + logic keyed on
   `source == 'incoming'` (the leak fix, done correctly — replacing the
   recipients-proxy first attempt). This is the first capability expressed
   correctly.
2. Extract `kind_profile` classification (pure, tested) with no behavior change.
3. Route the existing booleans through the capability map (behavior-preserving
   refactor; delete the duplication in v1/burn/batch).
4. Frontend: resolve kind once, split `ShowReceipt.vue` into per-kind layouts.
5. Retire `show_secret_link`'s "once" semantics or make the frontend honor it —
   pick one; today neither layer fully owns it.

Steps 2–5 are each independently shippable and reversible. Step 1 adds a field
but requires no data migration: the new `source` column defaults to `standard`,
and legacy incoming receipts age out via TTL (§4.1).
