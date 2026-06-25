C1 fix verification — atomic one-time consume
=============================================
Branch: claude/fix-one-time-reveal-atomicity (worktree /home/user/ots-work-c1)

Single-process sanity (claim_consumption!):
  CLAIM=true  EXISTS_AFTER=0   (winner deletes the key atomically)

Multi-process true-parallel race (12 independent processes, shared deadline),
mirroring clustered Puma — same harness that showed 12/12 BEFORE the fix:
  viewable=true : 12/12   (all pass the non-authoritative pre-check)
  won=true      : 1/12    (exactly one wins the atomic claim)
  got plaintext : 1/12    (only the winner discloses)

Before fix: 12/12 obtained the plaintext (see race_poc_output.md).
After fix : 1/12. One-time guarantee holds under concurrency.
