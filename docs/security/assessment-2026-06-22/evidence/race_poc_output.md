########## DETERMINISTIC (barrier after viewable? gate) ##########
[setup] created secret id=5ek73kxm1c5uu1ps…  exists=true
[result] threads=10  passed_viewable_gate+revealed_plaintext=10  destroy!_calls=10
[result] secret still present after run? no (consumed)
[VULNERABLE] One-time guarantee BROKEN: the same secret's plaintext was returned to 10 concurrent callers.

########## NATURAL race (NO barrier, simultaneous release, 50 threads) ##########
[result] threads=50  passed_viewable_gate+revealed_plaintext=1  destroy!_calls=1
[ok] plaintext returned to at most one caller.
[result] threads=50  passed_viewable_gate+revealed_plaintext=1  destroy!_calls=1
[ok] plaintext returned to at most one caller.
[result] threads=50  passed_viewable_gate+revealed_plaintext=1  destroy!_calls=1
[ok] plaintext returned to at most one caller.

########## MULTI-PROCESS TRUE-PARALLELISM (models multiple Puma workers) ##########
# 12 independent OS processes, each pre-loads the SAME secret, spin-waits to a
# shared wall-clock deadline, then runs load->viewable?->decrypt->revealed!.
# No shared GIL => genuine parallel execution, as in clustered Puma in production.
created secret id: durm29vdhu6n73ojlbt4czbcgvxe2s5845jwbff9j1h43gkvinks9tz4sm8vv7
WORKER pid=26624 viewable=true got=true
WORKER pid=26616 viewable=true got=true
WORKER pid=26613 viewable=true got=true
WORKER pid=26622 viewable=true got=true
WORKER pid=26615 viewable=true got=true
WORKER pid=26617 viewable=true got=true
WORKER pid=26614 viewable=true got=true
WORKER pid=26618 viewable=true got=true
WORKER pid=26620 viewable=true got=true
WORKER pid=26623 viewable=true got=true
WORKER pid=26621 viewable=true got=true
WORKER pid=26619 viewable=true got=true
[RESULT] 12 / 12 independent processes obtained the plaintext of the SAME one-time secret.
[CONCLUSION] One-time guarantee broken under real concurrency (multi-worker production).
