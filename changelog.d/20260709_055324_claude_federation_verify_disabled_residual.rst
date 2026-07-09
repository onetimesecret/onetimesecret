.. A new scriv changelog fragment.

Security
--------

- Federated subscription claims made without email verification are now
  surfaced by a loud, structured security-audit log. When a deployment turns
  email verification off (``verify_account`` disabled), the standard signup
  path still claims a matching cross-region subscription immediately because
  there is no verification step to defer to — an unavoidable residual of that
  configuration. ``CreateDefaultWorkspace`` now detects that risky combination
  (federation active *and* verification disabled) at claim time and logs the
  org, email-hash prefix, and plan, noting the benefit was applied with no
  proof of email ownership, so operators can spot abuse. Happy-path behavior is
  unchanged; verified customers and verify-enabled deployments never trip it.
  The residual is documented precisely in the workspace-creation operation and
  the account hooks, and a new full-stack integration spec drives the real
  Rodauth signup hook to prove the deferred (verify-enabled) and immediate
  (verify-disabled + audit) branches end-to-end.
