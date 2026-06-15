# locales/scripts/tests/test_i18n_cli.py

"""Characterization smoke suite for the consolidated i18n CLI.

The suite drives the *real* ``python3 locales/scripts/i18n ...`` entry point as
a subprocess against a throwaway tmp tree, isolated through the ``I18N_*``
environment overrides in :mod:`i18n.config`. It asserts behavioural
*invariants* -- determinism, no-loss round-trips, checksum verification --
rather than frozen golden bytes, so it stays green as locale content evolves
while still catching regressions in the tooling itself.

These are the properties the one-time differential verification proved (old
loose scripts vs the new package) frozen as executable, committed checks. The
old scripts are gone, so a true differential is no longer possible; these
invariants are the durable equivalent.

Runs two ways, no third-party dependency required (the CLI itself stays
zero-install; ``pytest`` is an optional convenience for contributors):

    python3 -m unittest discover -s locales/scripts/tests
    pytest locales/scripts/tests          # if pytest is installed
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# locales/scripts/tests/<this file>
#   parents[0] = tests   parents[1] = scripts   parents[2] = locales
SCRIPTS_DIR = Path(__file__).resolve().parents[1]
LOCALES_DIR = SCRIPTS_DIR.parent
I18N_ENTRY = SCRIPTS_DIR / "i18n"
REAL_EN = LOCALES_DIR / "content" / "en"
REAL_SCHEMA = LOCALES_DIR / "db" / "schema.sql"


def _en_slice(n: int = 4) -> list[Path]:
    """The ``n`` smallest real ``en`` files.

    Real files are guaranteed-valid inputs (no brittle hand-authored
    fixtures); the smallest keep each subprocess fast.
    """
    files = sorted(REAL_EN.glob("*.json"), key=lambda p: p.stat().st_size)
    return files[:n]


def _texts(locale_dir: Path) -> dict[str, str]:
    """Flatten ``{key: text}`` across every JSON file in a content locale dir."""
    out: dict[str, str] = {}
    for f in sorted(locale_dir.glob("*.json")):
        for key, val in json.loads(f.read_text("utf-8")).items():
            if isinstance(val, dict):
                out[key] = val.get("text", "")
    return out


def _dir_bytes(d: Path) -> dict[str, bytes]:
    """Snapshot ``{filename: raw bytes}`` for every JSON file in a dir."""
    return {p.name: p.read_bytes() for p in sorted(d.glob("*.json"))}


class I18nCliTestCase(unittest.TestCase):
    """Base case: a fresh env-isolated tmp tree + CLI runner per test."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="i18n-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

        self.content = self.tmp / "content"
        self.generated = self.tmp / "generated"
        self.db_dir = self.tmp / "db"
        (self.content / "en").mkdir(parents=True)
        self.db_dir.mkdir(parents=True)

        # init/migrate read SCHEMA_FILE == DB_DIR/schema.sql; seed the real one.
        shutil.copy(REAL_SCHEMA, self.db_dir / "schema.sql")
        for f in _en_slice():
            shutil.copy(f, self.content / "en" / f.name)

        self.env = {
            **os.environ,
            "I18N_CONTENT_DIR": str(self.content),
            "I18N_GENERATED_DIR": str(self.generated),
            "I18N_DB_DIR": str(self.db_dir),
        }

    def run_cli(
        self, *args: str, cwd: Path | None = None, env: dict | None = None
    ) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(I18N_ENTRY), *args],
            cwd=str(cwd) if cwd else None,
            env=env or self.env,
            capture_output=True,
            text=True,
        )

    def assertOk(
        self, proc: subprocess.CompletedProcess, msg: str = ""
    ) -> None:
        self.assertEqual(
            proc.returncode,
            0,
            f"{msg or 'command'} exited {proc.returncode}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}",
        )


class EnvSeamTest(I18nCliTestCase):
    """The production seam the rest of the suite depends on."""

    def test_overrides_redirect_every_surface(self) -> None:
        code = (
            f"import sys; sys.path.insert(0, r'{SCRIPTS_DIR}')\n"
            "import json, i18n.config as c\n"
            "print(json.dumps({"
            "'content': str(c.CONTENT_DIR), 'en': str(c.EN_DIR),"
            "'gen': str(c.GENERATED_DIR), 'dbdir': str(c.DB_DIR),"
            "'dbfile': str(c.DB_FILE), 'schema': str(c.SCHEMA_FILE)}))"
        )
        proc = subprocess.run(
            [sys.executable, "-c", code],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertOk(proc, "import config")
        cfg = json.loads(proc.stdout)
        self.assertEqual(cfg["content"], str(self.content))
        # EN_DIR and the default DB_FILE must cascade from the overridden dirs.
        self.assertEqual(cfg["en"], str(self.content / "en"))
        self.assertEqual(cfg["gen"], str(self.generated))
        self.assertEqual(cfg["dbdir"], str(self.db_dir))
        self.assertEqual(cfg["dbfile"], str(self.db_dir / "tasks.db"))
        self.assertEqual(cfg["schema"], str(self.db_dir / "schema.sql"))


class ContentCompileTest(I18nCliTestCase):
    def _compile(self, out: Path) -> subprocess.CompletedProcess:
        # compile is merged-only now: one nested JSON file per locale.
        return self.run_cli(
            "content", "compile", "--all", "--output-dir", str(out)
        )

    def test_compile_is_deterministic(self) -> None:
        a, b = self.tmp / "outA", self.tmp / "outB"
        self.assertOk(self._compile(a), "compile A")
        self.assertOk(self._compile(b), "compile B")
        names = sorted(p.name for p in a.glob("*.json"))
        self.assertIn("en.json", names)
        for name in names:
            self.assertEqual(
                (a / name).read_bytes(),
                (b / name).read_bytes(),
                f"{name} differs between two compiles (nondeterministic output)",
            )

    def test_compile_output_is_valid_nonempty_json(self) -> None:
        out = self.tmp / "out"
        self.assertOk(self._compile(out))
        data = json.loads((out / "en.json").read_text("utf-8"))
        self.assertTrue(data, "merged en.json compiled empty")


class ContentDecompileTest(I18nCliTestCase):
    """compile writes generated/locales; decompile recovers edits to content.

    Both ends use GENERATED_DIR (the I18N_GENERATED_DIR override ==
    ``self.generated``), so no ``--output-dir`` is needed -- compile lands
    exactly where decompile reads.
    """

    def test_source_roundtrip_is_lossless(self) -> None:
        before = _texts(self.content / "en")
        self.assertOk(self.run_cli("content", "compile", "en"), "compile en")
        self.assertTrue(
            (self.generated / "en.json").exists(),
            "compile en did not write the merged generated file",
        )
        self.assertOk(
            self.run_cli("content", "decompile", "en"), "decompile en"
        )
        self.assertEqual(
            before,
            _texts(self.content / "en"),
            "compile->decompile round-trip changed en content text",
        )

    def test_fallback_routes_via_source_layout(self) -> None:
        # The redesign delta: a key the target locale has not split into its own
        # files yet must route through the SOURCE locale's layout. en owns
        # web.A.x in auth.json; eo has no auth.json; an edited generated/eo.json
        # must land in a freshly created content/eo/auth.json.
        (self.content / "en" / "auth.json").write_text(
            '{"web.A.x": {"text": "Hello"}}', "utf-8"
        )
        self.generated.mkdir(parents=True, exist_ok=True)
        (self.generated / "eo.json").write_text(
            '{"web": {"A": {"x": "Saluton"}}}', "utf-8"
        )
        self.assertOk(
            self.run_cli("content", "decompile", "eo"), "decompile eo"
        )
        target = self.content / "eo" / "auth.json"
        self.assertTrue(
            target.exists(),
            "source-layout fallback did not create content/eo/auth.json",
        )
        data = json.loads(target.read_text("utf-8"))
        self.assertEqual(data["web.A.x"]["text"], "Saluton")


class ContentHashesTest(I18nCliTestCase):
    def test_hashes_adds_then_is_idempotent(self) -> None:
        # Append a bare new key (the documented form) lacking a content_hash.
        target = sorted((self.content / "en").glob("*.json"))[0]
        doc = json.loads(target.read_text("utf-8"))
        doc["web.TEST.idempotence"] = {"text": "Just testing hashes"}
        target.write_text(
            json.dumps(doc, ensure_ascii=False, indent=2), "utf-8"
        )

        self.assertOk(self.run_cli("content", "hashes"), "hashes (first)")
        first = _dir_bytes(self.content / "en")
        # The new key must have been populated with a content_hash.
        self.assertIn(
            "content_hash",
            json.loads(target.read_text("utf-8"))["web.TEST.idempotence"],
            "hashes did not populate content_hash for the new key",
        )

        self.assertOk(self.run_cli("content", "hashes"), "hashes (second)")
        self.assertEqual(
            first,
            _dir_bytes(self.content / "en"),
            "second hashes run was not a no-op (non-idempotent)",
        )


class DbRoundTripTest(I18nCliTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.assertOk(self.run_cli("db", "init"), "db init")

    def _glossary_count(self) -> int:
        proc = self.run_cli(
            "db", "query", "--json", "SELECT COUNT(*) AS c FROM glossary"
        )
        self.assertOk(proc, "count")
        return json.loads(proc.stdout)[0]["c"]

    def test_export_import_roundtrip(self) -> None:
        # gap #3: checksum-verified export -> wipe -> restore.
        self.assertOk(
            self.run_cli(
                "db",
                "query",
                "INSERT INTO glossary (locale, term, translation) "
                "VALUES ('eo', 'secret', 'sekreto')",
            ),
            "insert",
        )
        self.assertOk(self.run_cli("db", "export", "glossary"), "export")
        self.assertTrue((self.db_dir / "glossary.sql").exists())
        self.assertTrue((self.db_dir / "checksums.sha256").exists())

        self.assertOk(
            self.run_cli("db", "query", "DELETE FROM glossary"), "wipe"
        )
        self.assertEqual(self._glossary_count(), 0)

        self.assertOk(self.run_cli("db", "import"), "import")
        self.assertEqual(self._glossary_count(), 1)
        restored = self.run_cli(
            "db",
            "query",
            "--json",
            "SELECT translation FROM glossary WHERE term = 'secret'",
        )
        self.assertIn("sekreto", restored.stdout)

    def test_import_rejects_checksum_mismatch(self) -> None:
        self.assertOk(
            self.run_cli(
                "db",
                "query",
                "INSERT INTO glossary (locale, term, translation) "
                "VALUES ('eo', 'term', 'value')",
            ),
            "insert",
        )
        self.assertOk(self.run_cli("db", "export", "glossary"), "export")

        # Tamper with the SQL after its checksum was recorded.
        sql = self.db_dir / "glossary.sql"
        sql.write_text(sql.read_text("utf-8") + "\n-- tampered\n", "utf-8")

        self.assertOk(
            self.run_cli("db", "query", "DELETE FROM glossary"), "wipe"
        )
        proc = self.run_cli("db", "import")
        # Verify path must warn and skip; the row must stay gone.
        self.assertIn("mismatch", (proc.stdout + proc.stderr).lower())
        self.assertEqual(self._glossary_count(), 0)


class TasksFlowTest(I18nCliTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.assertOk(self.run_cli("db", "init"), "db init")

    def test_create_next_update_export_roundtrip(self) -> None:
        self.assertOk(self.run_cli("tasks", "create", "eo"), "create")
        nxt = self.run_cli("tasks", "next", "eo", "--json")
        self.assertOk(nxt, "next")
        task = json.loads(nxt.stdout)
        # task["keys"] is keyed by leaf name; the export lands under the full
        # dotted key (level_path + "." + leaf).
        leaf = next(iter(task["keys"]))
        full_key = f"{task['level_path']}.{leaf}"
        self.assertOk(
            self.run_cli(
                "tasks",
                "update",
                str(task["id"]),
                json.dumps({leaf: "TRADUKO"}),
            ),
            "update",
        )
        self.assertOk(self.run_cli("tasks", "export", "eo"), "export")
        landed = _texts(self.content / "eo")
        self.assertEqual(
            landed.get(full_key),
            "TRADUKO",
            "exported translation did not reach content/eo at the expected key",
        )

    def test_create_missing_only_enqueues_only_untranslated(self) -> None:
        # Mirror en into eo as if fully translated, then knock out ONE key so
        # exactly one untranslated key remains for --missing-only to find.
        import sqlite3

        eo = self.content / "eo"
        eo.mkdir(parents=True)
        victim: tuple[Path, str] | None = None
        for f in sorted((self.content / "en").glob("*.json")):
            data = json.loads(f.read_text("utf-8"))
            shutil.copy(f, eo / f.name)
            translatable = [
                k
                for k, v in data.items()
                if isinstance(v, dict)
                and not v.get("skip")
                and v.get("text", "") != ""
                and not k.startswith("_")
            ]
            if victim is None and len(translatable) >= 2:
                victim = (eo / f.name, translatable[0])
        self.assertIsNotNone(victim, "need an en file with >=2 translatable keys")
        path, missing_key = victim
        d = json.loads(path.read_text("utf-8"))
        del d[missing_key]
        path.write_text(json.dumps(d), encoding="utf-8")

        self.assertOk(
            self.run_cli("tasks", "create", "eo", "--missing-only"),
            "create --missing-only",
        )
        conn = sqlite3.connect(self.db_dir / "tasks.db")
        rows = conn.execute(
            "SELECT level_path, keys_json FROM translation_tasks "
            "WHERE locale='eo'"
        ).fetchall()
        conn.close()
        enqueued = [
            f"{level_path}.{leaf}"
            for level_path, keys_json in rows
            for leaf in json.loads(keys_json)
        ]
        self.assertEqual(
            enqueued,
            [missing_key],
            f"missing-only enqueued {enqueued}, expected only {missing_key}",
        )

    def test_export_skips_empty_translation_preserving_skip(self) -> None:
        # An empty/whitespace completed translation must not blank existing
        # content or strip an intentional skip flag on export.
        import sqlite3

        eo = self.content / "eo"
        eo.mkdir(parents=True)
        en_files = sorted((self.content / "en").glob("*.json"))
        data = json.loads(en_files[0].read_text("utf-8"))
        full_key = next(
            k
            for k, v in data.items()
            if isinstance(v, dict)
            and not v.get("skip")
            and v.get("text", "") != ""
            and not k.startswith("_")
        )
        level_path, _, leaf = full_key.rpartition(".")
        # Seed eo with this key intentionally skipped + a value to preserve.
        (eo / en_files[0].name).write_text(
            json.dumps({full_key: {"text": "KEEP", "skip": True}}),
            encoding="utf-8",
        )
        self.assertOk(self.run_cli("tasks", "create", "eo"), "create")
        db = sqlite3.connect(self.db_dir / "tasks.db")
        (task_id,) = db.execute(
            "SELECT id FROM translation_tasks "
            "WHERE locale='eo' AND file=? AND level_path=?",
            (en_files[0].name, level_path),
        ).fetchone()
        db.close()
        self.assertOk(
            self.run_cli(
                "tasks", "update", str(task_id), json.dumps({leaf: "   "})
            ),
            "update blank",
        )
        self.assertOk(self.run_cli("tasks", "export", "eo"), "export")
        after = json.loads((eo / en_files[0].name).read_text("utf-8"))
        self.assertEqual(
            after[full_key].get("text"),
            "KEEP",
            "empty translation blanked an existing value",
        )
        self.assertTrue(
            after[full_key].get("skip"),
            "empty translation stripped an intentional skip flag",
        )

    def test_next_human_header_uses_locale_not_hardcoded(self) -> None:
        # Regression: format_task_human once hardcoded 'Esperanto' as the third
        # column header for every locale.
        self.assertOk(self.run_cli("tasks", "create", "eo"), "create")
        proc = self.run_cli("tasks", "next", "eo")
        self.assertOk(proc, "next")
        self.assertIn("eo", proc.stdout)
        self.assertNotIn("Esperanto", proc.stdout)


class ValidateVariablesTest(I18nCliTestCase):
    def test_variables_json_runs(self) -> None:
        proc = self.run_cli("validate", "variables", "--json")
        self.assertOk(proc, "validate variables")
        data = json.loads(proc.stdout)
        self.assertIn("summary", data)


class ValidatePrGitDiffTest(I18nCliTestCase):
    """gap #1: default (non ``--files``) git-diff discovery + validation."""

    def _git(self, *args: str, cwd: Path) -> subprocess.CompletedProcess:
        proc = subprocess.run(
            ["git", *args],
            cwd=str(cwd),
            capture_output=True,
            text=True,
            # Insulate from the developer's global config / pre-commit hooks.
            env={**os.environ, "GIT_CONFIG_GLOBAL": os.devnull},
        )
        self.assertEqual(
            proc.returncode, 0, f"git {' '.join(args)} failed: {proc.stderr}"
        )
        return proc

    def test_pr_validates_git_changed_files(self) -> None:
        repo = self.tmp / "repo"
        cdir = repo / "locales" / "content"
        (cdir / "eo").mkdir(parents=True)
        (cdir / "en").mkdir(parents=True)
        (cdir / "en" / "auth.json").write_text(
            '{"web.A.x": {"text": "Hello {name}"}}', "utf-8"
        )
        (cdir / "eo" / "auth.json").write_text(
            '{"web.A.x": {"text": "Saluton {name}"}}', "utf-8"
        )

        self._git("init", "-q", cwd=repo)
        self._git("config", "core.hooksPath", os.devnull, cwd=repo)
        self._git("config", "user.email", "t@example.com", cwd=repo)
        self._git("config", "user.name", "t", cwd=repo)
        self._git("add", "-A", cwd=repo)
        self._git("commit", "-qm", "base", cwd=repo)
        base = self._git("rev-parse", "HEAD", cwd=repo).stdout.strip()
        # Fake the remote-tracking ref get_changed_locale_files diffs against
        # (origin/<base>...HEAD), so no real remote is needed.
        self._git("update-ref", "refs/remotes/origin/develop", base, cwd=repo)

        (cdir / "eo" / "auth.json").write_text(
            '{"web.A.x": {"text": "Saluton denove {name}"}}', "utf-8"
        )
        (cdir / "en" / "auth.json").write_text(
            '{"web.A.x": {"text": "Hello again {name}"}}', "utf-8"
        )
        self._git("add", "-A", cwd=repo)
        self._git("commit", "-qm", "change", cwd=repo)

        env = {**self.env, "I18N_CONTENT_DIR": str(cdir)}
        proc = self.run_cli(
            "validate",
            "pr",
            "--base",
            "develop",
            "--format",
            "json",
            cwd=repo,
            env=env,
        )
        self.assertOk(proc, "validate pr")
        summary = json.loads(proc.stdout)["summary"]
        # git discovery routed exactly the changed eo file; en (source) filtered.
        self.assertEqual(summary["files_checked"], 1)
        self.assertEqual(summary["locales"], ["eo"])


if __name__ == "__main__":
    unittest.main()
