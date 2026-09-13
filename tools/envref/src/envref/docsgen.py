#!/usr/bin/env python3
"""
generate-env-docs.py

Generates the environment-variable reference page in the docs site
(src/content/docs/en/self-hosting/environment-variables.md) from
.env.reference, and — via --check — fails CI when the committed page has
drifted from it.

WHY this exists: the docs page carried a hand-pasted copy of .env.reference
under a `### v0.25` heading. The app shipped v0.26.1, v0.26.2 and v0.26.3
without anyone re-pasting, so the page documented a release nobody was running
and silently omitted every variable added since. Hand-copying a 1900-line file
is not a process, it is a bet. This makes the copy mechanical and the staleness
detectable: .env.reference is the single source of truth, the page is a
derivative, and --check is the ratchet that keeps them equal.

Scope — only the mechanical part is generated:

    frontmatter + intro prose      hand-written, preserved verbatim
    <!-- BEGIN GENERATED ... -->
    variable reference             generated, overwritten on every run
    <!-- END GENERATED ... -->
    anything after END             hand-written, preserved verbatim

The sentinels are HTML comments, so they are invisible in the rendered page but
unambiguous to this script and to a human reading a diff. Everything outside
them survives regeneration untouched; everything inside is disposable.

English only. The other locales are translations fed by the existing
translation pipeline and are never touched here.

Since markers: emitted verbatim inside the fenced blocks, exactly as they
appear in .env.reference. This script never invents, parses or rewrites a
marker — annotate-config-versions.py owns them. It only notices whether any
exist, so it can emit the legend explaining them (and stay quiet before the
backfill lands).

Page shape — one `###` heading per section instead of one giant code block:

.env.reference already divides itself into 26 banner-delimited sections
(`# ═══` / `#  SECTION NAME` / `# ═══`). The old page flattened all of it into
a single fence. Regenerating into a single fence would make that worse, not
better: the source has grown from ~340 to ~1900 lines, and a 1900-line <pre>
has no anchors, no table of contents, and produces exactly one search hit for
the whole page. Splitting on the section banners the file already carries costs
nothing — the taxonomy is not invented here, it is read out of the source — and
buys per-section anchors, ToC entries and deep links.

The translation-cost argument against restructuring does not apply in practice:
the 8 locales that have this page at all have already diverged (they still
mirror the v0.24 layout, or are hand-written summaries pointing back at the
English page), and bin/translation-pluribus-util re-translates whole files with
no per-heading structural mapping to invalidate.

Deliberately NOT stamped into the page: the app version and a generation
timestamp. A timestamp breaks idempotence outright, and an app version makes
--check fail on a release that did not touch .env.reference — cross-repo
lockstep failure over a cosmetic string. Per-variable `# Since` markers carry
version information far better than the `### v0.25` heading that rotted ever
did, and nothing on the page can now go stale without .env.reference changing.

Usage:
  bin/envref docs                       # write ../docs.onetimesecret.com
  bin/envref docs ../some/docs/checkout # explicit docs repo path
  bin/envref docs --check               # CI drift guard, exit 1 on drift
  bin/envref docs --dry-run             # print the page, write nothing
  bin/envref docs --init                # one-time migration, see below

--init is the one-time bootstrap for a page that has no sentinels yet. It keeps
everything above the first `###` heading (frontmatter, intro prose, the
`## Environment Variables` heading and its lead sentence) and replaces
everything from there to end-of-file with the generated block. That discards
the hand-written v0.24 section, so it demands an explicit flag and lists the
headings it is about to remove: relocate any prose worth keeping to above the
BEGIN sentinel first, then run it. Every later run needs no flag.

WHERE --check RUNS: not in this repo, deliberately. The guard is
.github/workflows/env-reference-drift.yml in onetimesecret/docs.onetimesecret.com,
which checks out this repo at `main` and runs THIS script from there — one
implementation, no copy of the generator in the docs site.

It cannot live on this side. The page lives in another repo, so a PR that adds
a variable to .env.reference cannot update it in the same commit; an app-side
--check would therefore fail every variable-adding PR, blocking it on a docs PR
that cannot merge first. Reading .env.reference from `main` inverts the
dependency: the app PR merges, and the docs check stays red until the page is
regenerated. That ordering is spelled out in the docs workflow's header.

Drift is still bounded when no docs PR is open: that workflow runs nightly
(cron `17 6 * * *`) as well as on pull_request, so a variable added here is
caught within a day without anyone remembering to look.

Exit codes: 0 success / in sync, 1 drift or error.
"""

import difflib
import re
import sys
from pathlib import Path
from types import SimpleNamespace

from . import UsageError
from .paths import RootNotFound, repo_root

# Resolved at import so the constants below stay constants. Outside a checkout
# the resolver fails and ENV_REFERENCE simply will not exist, which run()
# already reports as "not found" — the same message the old path produced.
try:
    REPO_ROOT = repo_root()
except RootNotFound:
    REPO_ROOT = Path(".").resolve()
ENV_REFERENCE = REPO_ROOT / ".env.reference"

DEFAULT_DOCS_REPO = REPO_ROOT.parent / "docs.onetimesecret.com"
PAGE_RELPATH = Path("src/content/docs/en/self-hosting/environment-variables.md")

BEGIN_SENTINEL = "<!-- BEGIN GENERATED: .env.reference -->"
END_SENTINEL = "<!-- END GENERATED: .env.reference -->"

# The banner that delimits a section in .env.reference:
#   # ═══════════════════════════════════════════════════════════
#   #  SECRETS & CRYPTOGRAPHY
#   # ═══════════════════════════════════════════════════════════
BANNER_RE = re.compile(r"^#\s*═+\s*$")
BANNER_TITLE_RE = re.compile(r"^#\s*(.+?)\s*$")

# The marker recognizer, verbatim (docs/development/config-version-annotations.md).
# Used ONLY to decide whether the legend paragraph is warranted — never to
# parse or rewrite a marker.
SINCE_MARKER_RE = re.compile(r"[ \t]+# Since (v[0-9]+\.[0-9]+\.[0-9]+|unreleased)[ \t]*$")

# Section names are shouted in .env.reference. Title-casing them reads better as
# headings, but a naive .title() turns SSO into "Sso" and API into "Api". Tokens
# listed here keep their given form; everything else is title-cased.
ACRONYMS = {
    "API": "API",
    "AWS": "AWS",
    "CORS": "CORS",
    "CSP": "CSP",
    "DNS": "DNS",
    "HTTP": "HTTP",
    "IP": "IP",
    "OIDC": "OIDC",
    "OMNIAUTH": "OmniAuth",
    "SMTP": "SMTP",
    "SSL": "SSL",
    "SSO": "SSO",
    "TTL": "TTL",
    "UI": "UI",
    "URL": "URL",
}


def die(message):
    """Report a reason this command cannot run, and exit 2.

    2, not 1. This family documents 1 as "drift" and 2 as "bad input", and the
    single `return 1` below is the only drift there is here: the committed page
    differs from what .env.reference generates. Everything routed through die()
    is the other thing — a mistyped docs-repo path, mutually exclusive flags, a
    page whose sentinels are broken, a source file that cannot be parsed. None
    of those means the page drifted, and exiting 1 told every caller reading the
    code rather than the message that it had.
    """
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(2)


# --- .env.reference parsing ---------------------------------------------


def parse_env_reference(text):
    """Split .env.reference into (preamble, [(section_title, body), ...]).

    Preamble is everything before the first banner. A section body is
    everything between one banner and the next, with surrounding blank lines
    trimmed. Nothing is reflowed, reordered or rewritten.
    """
    lines = text.split("\n")
    preamble = []
    sections = []
    current_title = None
    current_body = []

    i = 0
    while i < len(lines):
        is_banner = (
            BANNER_RE.match(lines[i])
            and i + 2 < len(lines)
            and BANNER_RE.match(lines[i + 2])
        )
        if is_banner:
            title_match = BANNER_TITLE_RE.match(lines[i + 1])
            if not title_match:
                die(
                    f".env.reference line {i + 2}: banner with no section title "
                    f"({lines[i + 1]!r})"
                )
            if current_title is None:
                preamble = current_body
            else:
                sections.append((current_title, current_body))
            current_title = title_match.group(1)
            current_body = []
            i += 3
            continue
        current_body.append(lines[i])
        i += 1

    if current_title is None:
        die(".env.reference has no `# ═══` section banners — cannot generate")
    sections.append((current_title, current_body))

    return trim_blank_lines(preamble), [(t, trim_blank_lines(b)) for t, b in sections]


def trim_blank_lines(lines):
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def heading_text(raw_title):
    """`SSO / OMNIAUTH` -> `SSO / OmniAuth`, `BRANDING / PRIVATE-LABEL` -> `Branding / Private-Label`."""
    words = []
    for word in raw_title.split():
        parts = [ACRONYMS.get(p.upper(), p.capitalize()) for p in word.split("-")]
        words.append("-".join(parts))
    return " ".join(words)


# --- generation ----------------------------------------------------------


def fenced(body_lines):
    return ["```bash", *body_lines, "```"]


def header_paragraphs(lines):
    """Split .env.reference's header into paragraphs.

    Paragraphs here are separated by bare `#` lines, not blank ones —
    splitting on blanks alone sees the entire header as one paragraph.

    Factored out because two callers need the same split, and this file is
    part of a family whose recurring defect is the same rule spelled twice.
    """

    def is_separator(line):
        return not line.strip() or line.strip() == "#"

    paragraphs, current = [], []
    for line in lines:
        if is_separator(line):
            if current:
                paragraphs.append(current)
                current = []
        else:
            current.append(line)
    if current:
        paragraphs.append(current)
    return paragraphs


def marker_legend(lines):
    """The `# Since` legend, lifted from .env.reference rather than restated.

    This used to be hardcoded here, in prose that said the same thing as
    `.env.reference`'s header paragraph in different words — including the
    `docker --env-file` warning. Two authorings of one explanation drift, and
    this one drifted invisibly: `clean_preamble` drops the source paragraph
    before the page is assembled, so `--check` compared two copies of the
    hardcoded text and could never see the source change underneath it.

    Lifting it makes `.env.reference` the single source for its own
    conventions, which is the property this whole family of tools exists to
    hold. Returns None when the header has no such paragraph.
    """
    for para in header_paragraphs(lines):
        if "# Since" in "\n".join(para):
            return [re.sub(r"^#[ \t]?", "", line).rstrip() for line in para]
    return None


def clean_preamble(lines):
    """Drop the parts of .env.reference's header that are not documentation.

    Two paragraphs earn their place on the page: the [derived]/[independent]/
    [federation] legend, and the pointer to .env.example. Two do not — the file
    naming itself, which means nothing once the content is a web page, and its
    restatement of the `# Since` convention, which `marker_legend` has already
    emitted as prose immediately above. Reproducing either makes the page open
    by explaining a file the reader is not looking at.
    """
    paragraphs = header_paragraphs(lines)

    kept = []
    for para in paragraphs:
        text = "\n".join(para)
        if len(para) == 1 and para[0].strip().lstrip("#").strip() == ENV_REFERENCE.name:
            continue                      # "# .env.reference"
        if "# Since" in text:
            continue                      # duplicate of the legend above
        kept.append(para)

    out = []
    for index, para in enumerate(kept):
        if index:
            out.append("#")
        out += para
    return trim_blank_lines(out)


def build_generated_block(env_text):
    """Returns (lines between and including the two sentinels, section count)."""
    preamble, sections = parse_env_reference(env_text)

    out = [
        BEGIN_SENTINEL,
        "<!--",
        "  Generated by bin/envref docs in the onetimesecret repo,",
        "  from .env.reference. Do not edit between these markers: the next run",
        "  overwrites it. Edit .env.reference and regenerate instead.",
        "-->",
        "",
    ]

    # Applied per line, exactly as §1 specifies the recognizer.
    if any(SINCE_MARKER_RE.search(line) for line in env_text.split("\n")):
        legend = marker_legend(preamble)
        if legend is None:
            die(
                f"{ENV_REFERENCE.name} carries `# Since` markers but its header has no\n"
                "      paragraph explaining them, so the page would show markers it never\n"
                "      defines. Add one to the header — this script renders that paragraph\n"
                "      rather than keeping a second copy of it."
            )
        out += [*legend, ""]

    preamble = clean_preamble(preamble)
    if preamble:
        out += fenced(preamble)
        out.append("")

    for raw_title, body in sections:
        out.append(f"### {heading_text(raw_title)}")
        out.append("")
        out += fenced(body)
        out.append("")

    out.append(END_SENTINEL)
    return out, len(sections)


def render_page(page_lines, generated_block):
    """Splice generated_block into page_lines between the sentinels."""
    begin = end = None
    for index, line in enumerate(page_lines):
        if line.strip() == BEGIN_SENTINEL:
            if begin is not None:
                die(f"{PAGE_RELPATH}: two BEGIN sentinels — repair the page by hand")
            begin = index
        elif line.strip() == END_SENTINEL:
            if end is not None:
                die(f"{PAGE_RELPATH}: two END sentinels — repair the page by hand")
            end = index

    if begin is None and end is None:
        return None
    if begin is None or end is None:
        die(f"{PAGE_RELPATH}: only one sentinel present — repair the page by hand")
    if end < begin:
        die(f"{PAGE_RELPATH}: END sentinel precedes BEGIN sentinel")

    return page_lines[:begin] + generated_block + page_lines[end + 1 :]


def render_page_init(page_lines, generated_block):
    """One-time migration: keep everything above the first `###`, replace the rest."""
    cut = None
    for index, line in enumerate(page_lines):
        if line.startswith("### "):
            cut = index
            break
    if cut is None:
        cut = len(page_lines)

    # Reported on stderr so --init --dry-run keeps stdout to the page itself.
    # Only real markdown headings — `#` lines inside a fence are shell comments.
    dropped = []
    in_fence = False
    for line in page_lines[cut:]:
        if line.startswith("```"):
            in_fence = not in_fence
        elif not in_fence and re.match(r"^#{1,6}\s", line):
            dropped.append(line)
    if dropped:
        note = [
            f"NOTE: --init removes {len(page_lines) - cut} line(s) below the first",
            "      `###` heading, including these hand-written sections:",
            *[f"        {heading}" for heading in dropped],
            "      Relocate anything worth keeping above the BEGIN sentinel.",
        ]
        print("\n".join(note), file=sys.stderr)

    head = trim_trailing_blank(page_lines[:cut])
    return head + [""] + generated_block


def trim_trailing_blank(lines):
    end = len(lines)
    while end > 0 and not lines[end - 1].strip():
        end -= 1
    return lines[:end]


def normalize(lines):
    """Join lines into a file body with exactly one trailing newline."""
    return "\n".join(lines).rstrip("\n") + "\n"


# --- main ----------------------------------------------------------------


def run(
    docs_repo: str | None = None,
    *,
    check: bool = False,
    dry_run: bool = False,
    init: bool = False,
) -> int:
    """Generate the docs-site environment variables page from .env.reference.

    Parameters
    ----------
    docs_repo
        Path to the docs repo checkout. Defaults to a sibling checkout of
        docs.onetimesecret.com.
    check
        Exit 1 with a diff if the committed page differs from generated output.
    dry_run
        Print the page that would be written to stdout; write nothing.
    init
        One-time migration of a page that has no sentinels yet (destructive).
    """
    # argparse enforced this with a mutually exclusive group. Cyclopts has no
    # equivalent declaration, so the rule is stated here rather than lost.
    if check and dry_run:
        raise UsageError("--check and --dry-run are both read-only; pick one")
    args = SimpleNamespace(
        docs_repo=docs_repo if docs_repo is not None else str(DEFAULT_DOCS_REPO),
        check=check,
        dry_run=dry_run,
        init=init,
    )

    if args.check and args.init:
        die("--check and --init are mutually exclusive")

    if not ENV_REFERENCE.is_file():
        die(f"{ENV_REFERENCE} not found")

    page_path = Path(args.docs_repo).expanduser() / PAGE_RELPATH
    if not page_path.is_file():
        die(
            f"{page_path} not found.\n"
            f"      Pass the docs repo path as the first argument, e.g.\n"
            f"        bin/envref docs ../docs.onetimesecret.com"
        )

    env_text = ENV_REFERENCE.read_text(encoding="utf-8")
    generated_block, section_count = build_generated_block(env_text)

    current = page_path.read_text(encoding="utf-8")
    page_lines = current.split("\n")

    if args.init:
        expected = normalize(render_page_init(page_lines, generated_block))
    else:
        spliced = render_page(page_lines, generated_block)
        if spliced is None:
            die(
                f"{page_path} has no {BEGIN_SENTINEL} / {END_SENTINEL} pair.\n"
                f"      The page has not been migrated yet. Review, then run once:\n"
                f"        bin/envref docs {args.docs_repo} --init"
            )
        expected = normalize(spliced)

    if args.dry_run:
        sys.stdout.write(expected)
        return 0

    if args.check:
        if current == expected:
            print(f"PASS: {PAGE_RELPATH} matches .env.reference ({section_count} sections)")
            return 0
        diff = difflib.unified_diff(
            current.splitlines(keepends=True),
            expected.splitlines(keepends=True),
            fromfile=f"a/{PAGE_RELPATH} (committed)",
            tofile=f"b/{PAGE_RELPATH} (generated)",
        )
        print(
            f"FAIL: {PAGE_RELPATH} has drifted from .env.reference", file=sys.stderr
        )
        sys.stderr.writelines(diff)
        print("", file=sys.stderr)
        print(
            "Regenerate it in the docs repo and commit the result:", file=sys.stderr
        )
        print(
            f"  bin/envref docs {args.docs_repo}", file=sys.stderr
        )
        return 1

    if current == expected:
        print(f"PASS: {PAGE_RELPATH} already up to date ({section_count} sections)")
        return 0

    page_path.write_text(expected, encoding="utf-8")
    print(f"PASS: wrote {page_path} ({section_count} sections)")
    return 0
