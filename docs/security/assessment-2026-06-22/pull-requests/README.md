# Ready-to-open PR descriptions

Per the chosen workflow (push stacked branches, **no PRs opened**), these are
copy-paste-ready PR descriptions. All branches were committed only after a
fresh-agent review.

**Base branch:** `main` (or `develop` if that is your integration branch —
the branches are cut from commit `ef971b0`, the pre-assessment code state).

## Branch / stacking map

| PR | Branch | Base | Status |
|----|--------|------|--------|
| C1 | `claude/fix-one-time-reveal-atomicity` | main | pushed, reviewed ✅ |
| S1/S2 | `claude/fix-secure-header-defaults` | main | pushed, reviewed ✅ |
| #3499 PR-1 | `claude/fix-3499-resolve-omniauth-email` | main | pending review |
| SSO PR-2 | `claude/fix-sso-secure-linking` | `claude/fix-3499-resolve-omniauth-email` | pending |

C1 and S1/S2 are independent (either order). The SSO pair is **stacked**:
PR-2 targets PR-1's branch and must merge after it. PR-1 must NOT ship alone
with SSO enabled (it broadens email resolution before PR-2 adds the
account-linking guard).

Individual descriptions: `C1.md`, `S1-S2.md`, `PR1-resolve-omniauth-email.md`,
`PR2-sso-secure-linking.md`.
