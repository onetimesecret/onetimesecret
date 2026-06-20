# locales/scripts/i18n/console.py

"""Table rendering with an optional ``rich`` dependency.

This is the one intentional behavior change in the port, isolated here:
when ``rich`` is installed the output matches the legacy ``tasks/next.py``
rich-table styling (no box, bold header, folding overflow, width 160);
when it is not, a plain aligned-text table is produced instead.

JSON output paths in the CLI must never route through this module, so they
remain independent of whether ``rich`` is installed.
"""

from __future__ import annotations

from typing import Optional

try:  # rich is optional (declared under the [rich] extra)
    from rich.console import Console
    from rich.table import Table

    _HAS_RICH = True
except ImportError:  # pragma: no cover - exercised only without rich
    _HAS_RICH = False


def render_table(
    headers: list[str],
    rows: list[list[str]],
    col_styles: Optional[list[Optional[str]]] = None,
    widths: Optional[list[Optional[int]]] = None,
) -> str:
    """Render a table to a string.

    Args:
        headers: Column header labels.
        rows: Row data; each row is a list of cell strings aligned to headers.
        col_styles: Optional per-column rich style names (e.g. ``"cyan"``).
            Ignored in the plain-text fallback.
        widths: Optional per-column fixed widths. Used by rich for folding;
            in the fallback, treated as a minimum width per column.

    Returns:
        The rendered table as a single string (no trailing newline).
    """
    if _HAS_RICH:
        return _render_rich(headers, rows, col_styles, widths)
    return _render_plain(headers, rows, widths)


def _render_rich(
    headers: list[str],
    rows: list[list[str]],
    col_styles: Optional[list[Optional[str]]],
    widths: Optional[list[Optional[int]]],
) -> str:
    from io import StringIO

    table = Table(
        show_header=True, header_style="bold", box=None, pad_edge=False
    )
    for i, header in enumerate(headers):
        style = col_styles[i] if col_styles and i < len(col_styles) else None
        width = widths[i] if widths and i < len(widths) else None
        table.add_column(
            header,
            style=style,
            width=width,
            overflow="fold",
        )

    for row in rows:
        table.add_row(*[str(cell) for cell in row])

    output = StringIO()
    console = Console(file=output, force_terminal=False, width=160)
    console.print(table)
    return output.getvalue().rstrip("\n")


def _render_plain(
    headers: list[str],
    rows: list[list[str]],
    widths: Optional[list[Optional[int]]],
) -> str:
    ncols = len(headers)

    # Column width = max of header, longest cell, and any requested minimum.
    col_widths = [len(h) for h in headers]
    for row in rows:
        for i in range(ncols):
            cell = str(row[i]) if i < len(row) else ""
            col_widths[i] = max(col_widths[i], len(cell))
    if widths:
        for i in range(ncols):
            requested = widths[i] if i < len(widths) else None
            if requested is not None:
                col_widths[i] = max(col_widths[i], requested)

    lines = [
        " | ".join(h.ljust(col_widths[i]) for i, h in enumerate(headers))
    ]
    for row in rows:
        cells = [
            (str(row[i]) if i < len(row) else "").ljust(col_widths[i])
            for i in range(ncols)
        ]
        lines.append(" | ".join(cells))

    return "\n".join(lines)
