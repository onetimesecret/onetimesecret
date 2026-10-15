# Domain sender lifecycle

This reference is for developers changing custom-domain removal or sender
provisioning. It describes the current coordination between local sender
configuration and the sender identity registered at a mail provider. It is
an implementation reference, not a guarantee that provider cleanup succeeds.

## Shared sender identity lock

[MailerConfig.sender_identity_lock](../../lib/onetime/models/custom_domain/mailer_config.rb)
constructs a `Familia::Lock` with the name
`domain:#{domain_id}:sender_identity`. Here, `domain_id` is the custom domain's
internal identifier (`objid`), not its public `extid`.

The lock is separate from the config's related fields, so deleting the config
does not delete the held lock. These paths share it:

| Path | Work inside the critical section |
| --- | --- |
| [ProvisionSenderDomain](../../lib/onetime/operations/provision_sender_domain.rb) | Check config existence, provision at the provider, and persist results when persistence is enabled. |
| [DeleteSenderConfig](../../apps/api/domains/logic/sender_config/delete_sender_config.rb) | Remove the sender config, then tear down the provider identity using the removed config. |
| [Domains::Teardown](../../lib/onetime/operations/domains/teardown.rb) | Delete the external vhost, tear down the sender identity, then call the domain's `destroy!`. Shared by customer domain removal and the Colonel/CLI removal operation. Dry runs bypass teardown. |

Each path uses [SenderIdentityLease](../../lib/onetime/operations/sender_identity_lease.rb)
to renew the lock while provider calls block. Its `ensure` stops and joins the
renewer before attempting token-checked release, including when work inside
the critical section raises. Release errors are logged rather than masking
the operation's outcome. The shared operation callers own this locking;
[DeleteSenderDomain](../../lib/onetime/operations/delete_sender_domain.rb)
does not acquire the lock itself.

The Provision button, PUT/PATCH auto-provisioning, and
`bin/ots domains reconcile-sender` all call `ProvisionSenderDomain`, so they
use the same lock as removal:

- [Explicit provisioning](../../apps/api/domains/logic/sender_config/provision_sender_config.rb)
- [Auto-provisioning](../../apps/api/domains/logic/sender_config/auto_provisioning.rb)
- [Reconcile CLI](../../apps/api/domains/cli/reconcile_sender_command.rb)

## Why removal covers teardown through destruction

Domain removal deletes the provider identity before `CustomDomain#destroy!`
deletes the local sender config. Locking only the provider call would leave
this interleaving possible:

1. Removal deletes the provider identity and releases the lock.
2. Provisioning registers the identity again while the config still exists.
3. Removal destroys the domain and its config.

The new identity would have no local config pointing to it. Both removal
paths therefore acquire the lock before the first teardown step and release
it after `destroy!` exits, rather than between provider teardown and local
destruction.

Sender-config deletion uses a different order: it removes the config first,
then deletes the provider identity from the removed record. It holds the
same lock across both steps to prevent provisioning during that teardown.

## Shared teardown boundary

[Domains::Teardown](../../lib/onetime/operations/domains/teardown.rb) owns the
lease and destructive sequence, not the surrounding request or operator policy.
Its `call` contract separates contention, interrupted work, and committed work:

| Outcome | Contract | Caller handling |
| --- | --- | --- |
| Lock unavailable | Raises `Teardown::Busy` before provider teardown. | Translate to the caller's existing refusal contract. |
| Lease lost before `destroy!` returns | Raises `SenderIdentityLease::Lost`. Earlier provider calls may have changed remote state. | Report failure without claiming local destruction completed or that retry is safe. |
| `destroy!` returns and lease exit completes normally or raises `SenderIdentityLease::Lost` | Returns `Result` with `removal_committed: true` and an optional `lease_error` from the final ownership check. | Finalize committed work before surfacing `lease_error`. |
| Unexpected exception | Propagates unchanged. | Use the caller's existing exception handling; do not interpret the exception as proof of rollback. |

A returned result describes local destruction, not successful provider cleanup.
The operation retains the existing best-effort provider policy: it catches the
specified vhost transport errors and does not abort on a failed
`DeleteSenderDomain` result. It does not retry or reacquire a lost lease.

The [customer API](../../apps/api/domains/logic/domains/remove_domain.rb) retains
authorization, matching session-context cleanup, committed-loss logging, and
form-error translation. The [toolbox operation](../../lib/onetime/operations/domains/remove.rb)
retains previews, survivor-index repair, operator auditing, and its public
`SenderIdentityBusy` and `RemovalCommitted` exceptions. Both snapshot fields they
need before destruction clears the domain object.

This boundary keeps sequencing and its failure rules together without merging
caller policies. It is a domain-specific example, not a generic workflow engine:
there are no configurable steps or finalization callbacks. Sender-config-only
deletion remains separate because its local deletion precedes provider cleanup.
Future operations can use the same separation of execution, explicit outcomes,
and caller policy without adopting this lease or result type. Broader shared
infrastructure should follow demonstrated common behavior in another operation,
not anticipated extension points here.

## Configs loaded before removal

A caller can load a config before removal, then acquire the lock only after
removal finishes. Acquiring the lock alone does not make that in-memory
object current.

`ProvisionSenderDomain` checks `MailerConfig.exists_for_domain?` after
acquiring the lock and before calling the provider. If the config no longer
exists, it returns a failure and releases the lock without provisioning.
This check concerns record existence; it is not a general freshness check
for every field on the loaded config.

## Contention behavior

Lock acquisition does not wait for the current holder to finish:

- Customer domain removal and sender-config deletion raise a form error with
  `error_type: :conflict`. The current customer API responds with HTTP **422**,
  not 409.
- `Operations::Domains::Remove` raises `SenderIdentityBusy` before teardown.
  The refused apply is recorded as a failed audit attempt.
- The [Colonel adapter](../../apps/api/colonel/logic/colonel/remove_custom_domain.rb)
  translates `SenderIdentityBusy` into a form error with
  `error_type: :conflict`.
- The [removal CLI](../../lib/onetime/cli/domains/remove_command.rb) reports
  the operation's exception and exits nonzero.
- Provisioning returns a failed result indicating that another sender
  identity change is already in progress.

## Lease renewal and ownership loss

These paths acquire the lock with a **60-second TTL** and renew it every
**20 seconds** while the protected work runs. Renewal atomically checks the
owner token before extending the TTL. Step-boundary checks also renew the
lease, including between vhost deletion, sender teardown, and domain
destruction, and around provisioning's provider call.

A token mismatch, renewal error, or elapsed local deadline permanently marks
that lease as lost. The helper does not reacquire the lock and continue. A
checkpoint raises `SenderIdentityLease::Lost` before subsequent work; it
cannot interrupt a provider request already in flight.

Loss can occur after irreversible work. Failure reporting distinguishes it
from contention before teardown:

- Customer domain removal returns a conflict form error on loss. If
  destruction already committed, it first clears matching session domain
  context, logs the committed removal, and includes `removal_committed: true`
  in the form error's details.
- `Operations::Domains::Remove` completes finalization and records one
  success audit with `removal_committed: true` and `lease_lost: true` when
  destruction committed before loss was detected. It then raises
  `RemovalCommitted`, carrying the removed result. Loss before destruction
  follows the failed-attempt audit path instead.
- Sender-config deletion records a deletion event whenever local config
  removal committed, even if lease loss prevents provider teardown. The
  event includes the removed sender address, provider-cleanup state, and
  lease-loss status for reconciliation. Its conflict error reports whether
  the config was deleted and whether cleanup was attempted or completed.
- Provisioning returns a failed result on lease loss. A provider request
  already sent may have changed remote state even when the operation fails.

## Limits of this coordination

Renewal handles calls that outlast the initial lease while the renewer and
datastore remain available. It does not establish unbounded mutual exclusion:
a process pause or datastore failure can still allow expiry. Checkpoints do
not fence in-flight remote requests or make local writes conditional on the
lease token. There is no automatic rollback or recovery of partial work.

The lock also does not make provider changes and local destruction a single
transaction. `DeleteSenderDomain` returns failures as results, and domain
removal proceeds even if provider cleanup fails. Successful local removal
alone does not establish that the provider identity was deleted.

## Regression coverage

- [Teardown operation specs](../../spec/unit/onetime/operations/domains/teardown_spec.rb): sequencing and checkpoint failures; real datastore contention, renewal across slow vhost/sender/destruction steps, sticky watchdog failure, successor ownership, committed lease loss, and provisioning during removal or from a stale config afterwards.
- [Domain sender API integration specs](../../apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb): sender-config deletion and domain removal through HTTP with a real datastore lock; contention and lease-loss responses; committed-loss details, logging, and session cleanup. These specs stub provider teardown rather than contacting a live provider.
- [Customer removal logic specs](../../apps/api/domains/spec/logic/domains/remove_domain_spec.rb): shared-operation delegation, error translation, unchanged unexpected exceptions, and session/log finalization for committed outcomes.
- [Removal operation specs](../../spec/unit/onetime/operations/domains/remove_spec.rb): shared-operation delegation, preview and failure auditing, committed-outcome translation, and real datastore index repair including after committed lease loss.
- [Lease helper specs](../../spec/unit/onetime/operations/sender_identity_lease_spec.rb): renewal beyond a shortened initial TTL, sticky ownership loss, and token-safe cleanup.
- [Provisioning operation specs](../../spec/unit/onetime/operations/provision_sender_domain_spec.rb): rejection of a deleted config, renewal across slow provider/persistence work, and lease-loss handling.
- [Colonel adapter specs](../../apps/api/colonel/spec/logic/colonel/remove_custom_domain_spec.rb): translation of `SenderIdentityBusy` to a conflict form error.

Run Ruby specs through the [test lane runner](../../tests/lanes/README.md).
The API integration file belongs to the `simple` lane; the other files above
belong to `unit`. Run selections from different lanes separately.
