# locales/scripts/i18n/tokens.py

"""Single definition of "what is an interpolation/markup token".

Lifted verbatim out of :mod:`i18n.commands.validate` so the ``validate``
subcommands and ``tasks audit`` share one parser. This repo has twice been
bitten by twin normalizers drifting apart (issues #4023, #4047); a second token
regex is therefore not allowed. ``validate.py`` re-exports the names it used to
define so its call sites are unchanged.

Two views of the same patterns:

* :func:`extract_variables` -- the historical **set** view, returning exactly
  the three families (``vue``/``erb``/``printf``) the ``validate`` subcommands
  compare. Its shape is load-bearing (``check_empty_with_vars`` tests
  ``any(...)`` over ``.values()``), so nothing is added to it.
* :func:`extract_tokens` -- the **multiset** view over all five families
  documented in ``AGENT_TRANSLATION_PROTOCOL.md`` (``{var}``, ``{{var}}``,
  ``%{var}``, printf, ``<tag>``), used by ``tasks audit`` where dropping one of
  two ``{count}`` occurrences is a finding.
"""

from __future__ import annotations

import re
from collections import Counter
from typing import Any

# ---------------------------------------------------------------------------
# Patterns (identical in both legacy validate scripts -- do not "fix" them)
# ---------------------------------------------------------------------------

# Vue i18n: {variable} - use negative lookbehind to exclude ERB %{variable}
VUE_VAR_PATTERN = re.compile(r"(?<!%)(?<!\{)\{([a-zA-Z0-9_]+)\}")
ERB_VAR_PATTERN = re.compile(r"%\{([a-zA-Z0-9_]+)\}")
# NOTE: deliberately no word boundary. It fires on things like "100%discount"
# (%d). Pre-existing behaviour that every `validate variables` / `validate pr`
# baseline already tolerates -- tightening it here would change their output.
PRINTF_PATTERN = re.compile(r"%[sdifuxXoeEgGcp]")

# Mustache / Vue slot interpolation: {{var}} (optionally padded). Matched by
# NOTHING in the historical three patterns: VUE_VAR_PATTERN's (?<!\{) lookbehind
# kills the inner {var} and the outer position fails because `{` is not in
# [a-zA-Z0-9_]. Only used by the multiset view.
MUSTACHE_VAR_PATTERN = re.compile(r"\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}")

# Markup: <b>, </b>, <br/>, <a href="...">. Requires a letter after `<` so
# prose like "a < b" and "<3" never register.
TAG_PATTERN = re.compile(r"<(/?)([a-zA-Z][a-zA-Z0-9]*)(?:\s[^<>]*?)?\s*(/?)>")


def extract_variables(text: Any) -> dict[str, set[str]]:
    """Extract all variable patterns from a string.

    Accepts Any type for defensive validation of JSON values.

    Returns **sets** and exactly the three historical families; call sites in
    :mod:`i18n.commands.validate` do set arithmetic on the result. Use
    :func:`extract_tokens` when counts or the full five families matter.
    """
    if not isinstance(text, str):
        return {"vue": set(), "erb": set(), "printf": set()}

    return {
        "vue": set(VUE_VAR_PATTERN.findall(text)),
        "erb": set(ERB_VAR_PATTERN.findall(text)),
        "printf": set(PRINTF_PATTERN.findall(text)),
    }


def normalize_tag(closing: str, name: str, self_closing: str) -> str:
    """Canonical rendering of a markup tag: ``<b>`` / ``</b>`` / ``<br/>``.

    Attributes are dropped on purpose. Comparing ``<a href="/x">`` verbatim
    would flag benign quoting/ordering differences; the protocol rule is that
    the *tag* survives translation. Losing an attribute is therefore a false
    negative we accept in exchange for a quiet check.
    """
    return f"<{closing}{name}{self_closing}>"


def extract_tokens(text: Any) -> Counter[str]:
    """Multiset of every interpolation/markup token in ``text``.

    Keys are the tokens as an operator would grep for them (``{count}``,
    ``{{count}}``, ``%{count}``, ``%s``, ``<b>``); values are occurrence counts.
    Non-string input yields an empty Counter.
    """
    counts: Counter[str] = Counter()
    if not isinstance(text, str):
        return counts

    # {{var}} first, then blank it out, so a mustache token can never also be
    # counted as a vue token. (The lookbehinds already guarantee that today;
    # not depending on them keeps the two families independent.)
    for match in MUSTACHE_VAR_PATTERN.finditer(text):
        counts[f"{{{{{match.group(1)}}}}}"] += 1
    rest = MUSTACHE_VAR_PATTERN.sub(" ", text)

    for name in VUE_VAR_PATTERN.findall(rest):
        counts[f"{{{name}}}"] += 1
    for name in ERB_VAR_PATTERN.findall(rest):
        counts[f"%{{{name}}}"] += 1
    for spec in PRINTF_PATTERN.findall(rest):
        counts[spec] += 1
    for closing, name, self_closing in TAG_PATTERN.findall(rest):
        counts[normalize_tag(closing, name, self_closing)] += 1

    return counts


def strip_tokens(text: str) -> str:
    """``text`` with every token removed -- what a human is asked to translate.

    Used by the ``tasks audit`` English-leak check to tell "this string is one
    bare placeholder" from "this string is untranslated prose".
    """
    if not isinstance(text, str):
        return ""
    out = MUSTACHE_VAR_PATTERN.sub(" ", text)
    out = ERB_VAR_PATTERN.sub(" ", out)
    out = VUE_VAR_PATTERN.sub(" ", out)
    out = PRINTF_PATTERN.sub(" ", out)
    out = TAG_PATTERN.sub(" ", out)
    return out
