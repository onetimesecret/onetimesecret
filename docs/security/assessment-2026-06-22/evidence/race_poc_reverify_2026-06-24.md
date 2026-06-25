# C1 one-time race — re-verification evidence (2026-06-24)

> Saved as `.md` (not `.txt`) because `.gitignore:5` ignores `*.txt` — which is why the
> original assessment's `evidence/*.txt` was never committed. Captured program output below.

```
C1 one-time race — INDEPENDENT RE-VERIFICATION capture
Date: 2026-06-24   Stack: ruby 3.4.9, familia 2.11.0, otto 2.3.1, rhales 0.7.1, Valkey :2121
NOTE: the original assessment referenced evidence/race_poc_output.txt but it was never committed;
      this file is a regenerated, equivalent capture produced during the 2026-06-24 re-verification.
PoC scripts (adapted to this worktree's RACK_ENV=test config resolution; logic unchanged):
      scratchpad/c1_race_model.rb, c1_mp_setup.rb, c1_mp_worker.rb (from docs/.../poc/race_reveal_model.rb)
============================================================

## A. Model-level barrier PoC (deterministic; models the production multi-process interleave)
[env] familia=2.11.0 ruby=3.4.9 redis=redis://127.0.0.1:6379/0
[setup] created secret id=2zedqjwla6rjcnvj…  exists=true
[result] threads=10  passed_gate+got_plaintext=10  destroy!_calls=10
[result] secret still present after run? no (consumed)
[VULNERABLE] one-time guarantee BROKEN: same plaintext returned to 10 concurrent callers.

## B. True multi-process PoC (12 independent OS processes, no shared GIL, shared consume barrier)
[setup] secret id=ijsw0xmhav4ra8yc…  present_before=1
[barrier] all 12 workers consume at epoch=1782350000.65
GOT 12050 MP-RACE-CANARY-11946
GOT 12051 MP-RACE-CANARY-11946
GOT 12052 MP-RACE-CANARY-11946
GOT 12053 MP-RACE-CANARY-11946
GOT 12054 MP-RACE-CANARY-11946
GOT 12055 MP-RACE-CANARY-11946
GOT 12056 MP-RACE-CANARY-11946
GOT 12057 MP-RACE-CANARY-11946
GOT 12058 MP-RACE-CANARY-11946
GOT 12059 MP-RACE-CANARY-11946
GOT 12060 MP-RACE-CANARY-11946
GOT 12061 MP-RACE-CANARY-11946
[RESULT] independent processes that obtained the plaintext: 12 / 12
[RESULT] secret key present after run? 0 (0 = consumed/deleted)

## C. In-process full-stack PoC via the REAL /api/v2/secret/:id/reveal endpoint (GIL-bound control)
   Expected ~1/N: within one MRI process the GIL serialises the CPU-bound reveal, masking the race.
   (Confirms the assessment's own explanation for why a single process hid the bug.)
```
