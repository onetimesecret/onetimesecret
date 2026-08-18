#!/usr/bin/env python3
"""
Report whether a locale's derived register can actually enforce anything.

WHY THIS EXISTS. `lint_content.py` (translation-rules, run by
`.github/workflows/validate-register.yml` and by `export-all.sh`) scans shipped
content for the tokens in `register.forbidden_tokens`. When that list is EMPTY
the linter has nothing to search for, so it skips every string and exits 0 with
"0 string(s) scanned" -- a clean pass that is INDISTINGUISHABLE from "checked
the whole corpus and found nothing". Observed this round:

    de     0 string(s) scanned      forbidden_tokens=0
    ar     0 string(s) scanned      forbidden_tokens=0
    uk     3986 string(s) scanned   forbidden_tokens=17

de is form=informal/pronoun=du and got ZERO automated register enforcement while
its sibling de_AT got 10 tokens; nothing in the pass/fail signal said so. This
tool makes the difference explicit and loud, so an empty ruleset can never be
mistaken for enforcement.

It reports two more things a green lint cannot tell you: prohibitions that live
in `register_spec` only (vi's kinship pronouns, ar's dialect markers -- real
policy the token engine cannot match), and a `pronoun` / `possessive`
capitalization disagreement in the artifact itself (ru declares pronoun "вы" but
possessives ["Ваш", ...]; the lint engine casefolds, so no capitalization rule is
enforceable for any locale).

EXIT SEMANTICS ARE DELIBERATELY UNCHANGED: an empty ruleset is a WARNING, not a
failure -- several empty lists are correct (ar's dialect markers are substrings
of valid MSA words and cannot be tokenized at all). Callers that want the
burndown to block can opt in with --fail-on-empty; no caller does today.

Usage:
    python3 locales/scripts/register-coverage.py \
        --resolved generated/i18n/.resolved/de.json
    python3 locales/scripts/register-coverage.py --format github --resolved ...
    python3 locales/scripts/register-coverage.py --json --resolved ...

Exit codes (mirroring lint_content.py's convention):
    0  reported (enforcing OR empty -- read the WARNING line)
    1  --fail-on-empty was passed and the locale enforces nothing
    2  usage/config error (model missing or not readable JSON)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

# register_spec is the free-form upstream extension that carries the half of a
# register policy which CANNOT be tokenized (vi's kinship pronouns
# anh/cô/chú/bác that collide with "tiếng Anh"/"ghi chú"; ar's dialect markers
# that are substrings of valid MSA words). Any list-of-strings under a key whose
# name mentions one of these is policy the lint engine does NOT enforce, so we
# count it separately instead of letting it read as coverage.
POLICY_ONLY_KEY_HINTS = ("forbidden", "not_tokenized", "banned")


def _load_resolved(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise _Usage(f"resolved model not found: {path}") from exc
    except (json.JSONDecodeError, OSError) as exc:
        raise _Usage(f"resolved model is not readable JSON: {path}: {exc}") from exc


class _Usage(Exception):
    """A usage/config error -> exit 2."""


def _policy_only_terms(node: Any, key_hinted: bool = False) -> list[str]:
    """Every string leaf reachable under a `register_spec` key that names a
    prohibition (see POLICY_ONLY_KEY_HINTS). Free-form by contract, so this
    walks rather than assuming vi's or ar's particular shape."""
    if isinstance(node, dict):
        out: list[str] = []
        for key, value in node.items():
            hinted = key_hinted or any(h in key.lower() for h in POLICY_ONLY_KEY_HINTS)
            out.extend(_policy_only_terms(value, hinted))
        return out
    if isinstance(node, list):
        out = []
        for item in node:
            out.extend(_policy_only_terms(item, key_hinted))
        return out
    if isinstance(node, str) and key_hinted:
        return [node]
    return []


def _casing_conflict(register: dict[str, Any]) -> bool:
    """True when the register's own `pronoun` and `possessive` disagree about
    capitalization (ru: pronoun "вы" lowercase, possessive ["Ваш", ...]
    capitalized).

    Capitalization is load-bearing in several locales -- ru's rule says the
    formal forms are "capitalized when directly addressing the user" -- but the
    resolved model has no field for it, and the lint engine casefolds both sides
    (translation-rules lib/resolver/matching.py `_casefold`), so no
    capitalization rule is checkable at all. When the two casing signals in the
    artifact disagree, a consumer keying off either one asserts the wrong casing:
    that is worth a warning, not a silent guess."""
    pronoun = register.get("pronoun")
    possessive = register.get("possessive") or []
    if not isinstance(pronoun, str) or len(pronoun.split()) != 1 or not possessive:
        return False
    upper = {p[:1].isupper() for p in possessive if isinstance(p, str) and p}
    return len(upper) > 1 or (upper and pronoun[:1].isupper() not in upper)


def assess(locale: str, resolved: dict[str, Any]) -> dict[str, Any]:
    """Coverage verdict for one resolved model. Pure: callers supply the parsed
    model so this stays free of I/O."""
    register = resolved.get("register")
    tokens = list((register or {}).get("forbidden_tokens") or [])
    policy_only = _policy_only_terms((register or {}).get("register_spec"))
    return {
        "casing_conflict": bool(register) and _casing_conflict(register),
        "locale": locale,
        "has_register": register is not None,
        "form": (register or {}).get("form"),
        "pronoun": (register or {}).get("pronoun"),
        "forbidden_token_count": len(tokens),
        "forbidden_tokens": [t.get("token") for t in tokens if isinstance(t, dict)],
        # Documented-but-unenforceable prohibitions. Zero at translation-rules
        # v0.1.1: the resolver's _build_register drops register_spec from the
        # emitted model (lib/resolver/model.py), so no consumer can see them --
        # filed upstream. This surfaces them the moment that lands.
        "policy_only_count": len(policy_only),
        "policy_only_terms": policy_only,
        "enforcing": bool(tokens),
    }


def _lines(verdict: dict[str, Any]) -> list[tuple[str, str]]:
    """(level, message) pairs; level is "warning" or "notice"."""
    locale = verdict["locale"]
    if not verdict["has_register"]:
        return [
            (
                "warning",
                f"{locale}: resolved model has NO register block — this locale is "
                f"NOT register-governed and the register lint cannot fail on it. "
                f"A clean lint here means 'nothing checked', not 'nothing wrong'.",
            )
        ]
    if not verdict["enforcing"]:
        # ar's pronoun is a descriptive sentence, not a pronoun; keep the line
        # readable in CI logs.
        pronoun = verdict["pronoun"]
        if isinstance(pronoun, str) and len(pronoun) > 48:
            pronoun = pronoun[:45] + "..."
        extra = ""
        if verdict["policy_only_count"]:
            extra = (
                f" {verdict['policy_only_count']} prohibition(s) are documented in "
                f"register_spec but are not machine-checkable."
            )
        return [
            (
                "warning",
                f"{locale}: register.forbidden_tokens is EMPTY (form="
                f"{verdict['form']}, pronoun={pronoun!r}) — the register "
                f"lint scans 0 strings and CANNOT fail. This locale has no "
                f"automated register enforcement; a green lint means 'nothing "
                f"checked', not 'nothing wrong'.{extra} Fix belongs upstream in "
                f"translation-rules (rules/locales/{locale}/register.yaml).",
            )
        ]
    out = [
        (
            "notice",
            f"{locale}: {verdict['forbidden_token_count']} forbidden token(s) "
            f"enforced (form={verdict['form']}).",
        )
    ]
    if verdict["casing_conflict"]:
        out.append(
            (
                "warning",
                f"{locale}: register.pronoun ({verdict['pronoun']!r}) and "
                f"register.possessive disagree about capitalization, and the "
                f"resolved model has no field for a capitalization rule. The lint "
                f"engine casefolds, so capitalization is NOT enforced for any "
                f"locale — a green lint says nothing about it.",
            )
        )
    if verdict["policy_only_count"]:
        out.append(
            (
                "warning",
                f"{locale}: {verdict['policy_only_count']} additional prohibition(s) "
                f"live in register_spec only and are NOT lint-enforced: "
                f"{', '.join(verdict['policy_only_terms'][:12])}",
            )
        )
    return out


def _emit(verdict: dict[str, Any], github: bool) -> None:
    for level, message in _lines(verdict):
        if github:
            print(f"::{level}::{message}")
        elif level == "warning":
            print(f"WARNING: {message}", file=sys.stderr)
        else:
            print(f"OK: {message}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="register-coverage.py",
        description="Report whether a locale's derived register enforces anything.",
    )
    parser.add_argument(
        "--resolved",
        required=True,
        help="Path to the derived generated/i18n/.resolved/<locale>.json.",
    )
    parser.add_argument(
        "--locale",
        default=None,
        help="Locale label for output (default: the model's _meta.locale, else "
        "the --resolved filename stem).",
    )
    parser.add_argument(
        "--format",
        choices=("text", "github"),
        default="text",
        help="text (default) or github (::warning::/::notice:: annotations).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the structured verdict as JSON to stdout instead of text.",
    )
    parser.add_argument(
        "--fail-on-empty",
        action="store_true",
        help="Exit 1 when the locale enforces nothing. OFF by default: several "
        "empty registers are correct (ar), so this is an opt-in burndown gate, "
        "never the default CI behaviour.",
    )
    args = parser.parse_args(argv)

    try:
        path = Path(args.resolved)
        resolved = _load_resolved(path)
        locale = args.locale or resolved.get("_meta", {}).get("locale") or path.stem
        verdict = assess(locale, resolved)
    except _Usage as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(verdict, ensure_ascii=False, indent=2))
    else:
        _emit(verdict, github=args.format == "github")

    return 1 if (args.fail_on_empty and not verdict["enforcing"]) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
