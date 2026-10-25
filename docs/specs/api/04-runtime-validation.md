# 4. Runtime response validation

Status: Proposed. Depends on [creation failure semantics](02-creation-failures.md), not a recovery service.

## Purpose and scope

Creation and memo consumers accept validated operation-specific data. A malformed response does not prove that the mutation failed.

## Requirements

- Creation responses are validated before success consumers or navigation use them.
- Independently valid receipt handles may be retained when other response fields fail validation; unchecked fields are not used.
- Missing or invalid handles produce an outcome-unknown message, without automatic POST retry or a promise of recovery.
- Memo responses match the requested receipt and update only its validated memo.
- An uncertain memo write is not automatically repeated. Failed refresh validation preserves the previous list and exposes an error.
- Background refresh never consumes the generated-value display through ordinary receipt GET.

## Acceptance

Malformed bodies, mismatched identifiers and response loss cannot cause unchecked updates or automatic duplicate writes. Validation failures remain distinguishable from confirmed server rejection. Existing one-time display and receipt-only browser persistence boundaries remain unchanged.

## Exclusions and open decisions

No client recovery endpoint, plaintext persistence or new concurrency protocol. The minimal handle schema, uncertainty wording and authorized non-revealing memo refresh path require selection before implementation.
