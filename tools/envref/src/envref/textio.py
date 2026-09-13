"""Reading an annotated config file as text.

Every recognizer in this family anchors a marker to end-of-line, and CR is not
blank, so on a CRLF worktree a marker is simply not there as far as the
recognizer is concerned. Nothing in `.gitattributes` forces LF on these files,
so `core.autocrlf=true` — the Windows default — produces exactly that state.

That was found three times in three readers before it was read as one bug:
the ratchet reported all 603 markers malformed, the release step reported
"nothing to do" and shipped `unreleased` in a tag, and the map generator lost
99 of 431 keys. Each was the same line of reasoning rediscovered, which is the
signature of a rule spelled once per reader. This is the one spelling.

`annotate.py` deliberately does NOT use this. It rewrites these files, so it
has to put every byte back exactly as it found it; `read_lines()` splits the CR
off each body and `join_lines()` restores it, which is the same normalisation
expressed so that a write is a byte no-op. `tests/test_line_endings.py` asserts
the two agree.
"""

from pathlib import Path

__all__ = ["read_text"]


def read_text(path: str | Path) -> str:
    """File contents as text, with CRLF line endings normalised to LF.

    A lone CR is left alone rather than treated as a line ending: it is not a
    line ending on any platform this runs on, and silently rewriting one would
    hide a corrupt file instead of letting the caller notice it. annotate.py
    refuses such a file outright, so translating one here would open the same
    asymmetry this module exists to close — the readers would see a line
    boundary where the writer sees a corrupt file.

    Reading bytes and decoding is what makes that true. Path.read_text() applies
    universal-newline translation and turns a lone CR into "\n" before this
    function sees it — the silent rewrite the paragraph above rules out — and
    its newline= parameter is Python 3.13+, while this package supports 3.11.
    It is also exactly how annotate.read_lines() reads the same files, which is
    the point: one definition, reached two ways only because one of them has to
    put the bytes back.
    """
    return Path(path).read_bytes().decode("utf-8").replace("\r\n", "\n")
