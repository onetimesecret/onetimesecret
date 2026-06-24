# i18n CLI tests

Characterization smoke suite for the consolidated `i18n` CLI. It drives the real
`python3 locales/scripts/i18n ...` entry point as a subprocess against a
throwaway tmp tree, isolated through the `I18N_*` path overrides in
`i18n.config`. It asserts behavioural *invariants* (determinism, no-loss
round-trips, checksum verification) rather than frozen golden bytes, so it stays
green as locale content evolves while still catching regressions in the tooling.

These freeze, as executable checks, the properties the one-time differential
verification proved (old loose scripts vs the consolidated package). The old
scripts are gone, so a true differential is no longer possible; these invariants
are the durable equivalent.

## Running

The CLI is zero-install, and so is the suite — it runs on the standard library:

```bash
# from the repo root
python3 -m unittest discover -s locales/scripts/tests

# or, if you prefer pytest (optional: `pip install -e locales/scripts[test]`)
pytest locales/scripts/tests
```

## Isolation

Every test runs against a fresh `tempfile.mkdtemp()` tree, never the real repo.
The four `I18N_*` overrides relocate each filesystem surface:

| Override | Surface |
| --- | --- |
| `I18N_CONTENT_DIR` | source-of-truth flat-key JSON tree |
| `I18N_GENERATED_DIR` | app-consumable merged compiled output |
| `I18N_DB_DIR` | schema / exports / working-DB directory |
| `I18N_DB_FILE` | the working SQLite file (defaults under `DB_DIR`) |

Source fixtures are a small slice of the real `content/en` files (guaranteed
valid, fast), so assertions target invariants, not specific key values.
