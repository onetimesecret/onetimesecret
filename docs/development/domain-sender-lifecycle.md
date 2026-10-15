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
| [RemoveDomain](../../apps/api/domains/logic/domains/remove_domain.rb) | Delete the external vhost, tear down the sender identity, then call the domain's `destroy!`. |
| [Operations::Domains::Remove](../../lib/onetime/operations/domains/remove.rb) | The same teardown sequence for the Colonel endpoint and domain-removal CLI. Dry runs do not acquire the lock. |

Each path releases its acquired token in `ensure`, including when work inside
the critical section raises. The shared operation callers own this locking;
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

## Limits of this coordination

These paths acquire the lock with a **60-second TTL**. They do not renew the
lease or fence provider calls and datastore writes against lease expiry.
An operation that outlasts its lease can overlap a later holder. In
particular, domain removal includes the external vhost call within that
same lease. The lock does not establish unbounded mutual exclusion.

The lock also does not make provider changes and local destruction a single
transaction. `DeleteSenderDomain` returns failures as results, and domain
removal proceeds even if provider cleanup fails. Successful local removal
alone does not establish that the provider identity was deleted.

## Regression coverage

- [Domain sender API integration specs](../../apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb): sender-config deletion and domain removal with a real datastore lock; contention refusal; lock coverage through destruction; provisioning during removal and from a stale config afterwards. These specs stub provider teardown rather than contacting a live provider.
- [Customer removal logic specs](../../apps/api/domains/spec/logic/domains/remove_domain_spec.rb): lock acquisition/release order, refusal before teardown, and release when destruction raises.
- [Removal operation specs](../../spec/unit/onetime/operations/domains/remove_spec.rb): mocked ordering and failure auditing, plus real datastore checks for contention and stale-config provisioning.
- [Provisioning operation specs](../../spec/unit/onetime/operations/provision_sender_domain_spec.rb): rejection of a deleted config and lock release.
- [Colonel adapter specs](../../apps/api/colonel/spec/logic/colonel/remove_custom_domain_spec.rb): translation of `SenderIdentityBusy` to a conflict form error.

Run Ruby specs through the [test lane runner](../../tests/lanes/README.md).
The API integration file belongs to the `simple` lane; the other files above
belong to `unit`. Run selections from different lanes separately.
