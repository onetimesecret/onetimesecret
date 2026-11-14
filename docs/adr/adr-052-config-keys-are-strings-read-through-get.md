---
id: "052"
status: proposed
title: "ADR-052: Config Keys Are Strings, and Code Reads Config Through get"
---

## Status

Proposed

## Date

2026-11-14

## Context

The main config (`OT.conf`) is a Hash loaded from
`etc/defaults/config.defaults.yaml` and the operator's file. Code read it in
several ways: `OT.conf.dig('site', 'host')`, `OT.conf['site']['host']`,
`OT.conf.fetch('site', {})`, each followed by its own `|| default`. Two
things made a wrong read silent:

- **Key type.** Keys were converted to Strings only when the defaults file
  was layered under the operator file. An explicit-path load, or a load
  without the defaults file, kept Symbol keys from `:key:` YAML. Several
  readers guarded against both forms (`h[:k] || h['k']`,
  `transform_keys(&:to_s)`), and a Symbol read on a String-keyed section
  returned nil.
- **Path.** `dig` returns nil for a path that does not exist, the same as
  for a setting that is unset. A typo or a stale path was indistinguishable
  from an unset value, and the `|| default` that followed hid it.

Issue #3991 tracks this work. Its census of every config read found reads
of paths the config does not have, each returning nil in every install: a
logger reading `Onetime.conf[:environment]`, V1 reading `site.domains` for
`features.domains`, auth emails reading `site.product_name` for
`brand.product_name`, a billing check reading a `billing` section that is a
separate config object.

## Decision

1. **Every key in the loaded config is a String**, on every load path.
   `Config.after_load` converts the whole tree. Two keys on one level with
   the same String form (`:host:` and `host:`) stop boot with a
   `ConfigError` naming the key. Values keep their type (Symbol values are
   allowed).
2. **Code in `lib/` and `apps/` reads the config through
   `OT.conf.get(path[, default])`.** The path is dotted
   (`'site.admin.elevation'`), or an Array of Strings when a segment is a
   variable. Without a default the setting is required: a path that is not
   in the config raises `MissingPathError` with the path, and a value an
   operator sets to nil reads as nil. With a default the setting is
   optional. `false` and `0` are values and are never replaced by the
   default. A path that runs through a non-Hash value raises
   `PathTypeError`, with or without a default.
3. **A spec enforces both.** `spec/unit/onetime/config/access_guard_spec.rb`
   parses `lib/` and `apps/` with Prism. It fails on any use of `OT.conf`
   other than `.get` that is not listed with a reason, on a required path
   the shipped config does not have, and on an optional path that is not
   listed in `OPTIONAL_PATHS` with the reason it can be absent. In test
   runs, `Onetime::Config::StrictKeys` makes every Hash in the config tree
   raise on a non-String key, which catches Symbol reads on a section that
   `get` returned.

A dotted path needs one key type, and Strings are what YAML and the
defaults file produce. Raising on a missing required path follows
`Hash#fetch` and `ENV.fetch`: the caller states whether a value may be
absent, and the guard can check that statement against the shipped config
before the code runs.

`OT.conf` stays a plain Hash with `get` added to the root instance, so tests
and tools can still read, write and serialize it as a Hash.

## Trade-offs

- **We lose:** the freedom to read config with the Hash API in application
  code. Each optional setting that the defaults file does not define needs
  an `OPTIONAL_PATHS` entry, and code that hands the whole config to a
  library (`Strategy.for_config(OT.conf)`) needs an `ALLOWED_USES` entry.
- **We gain:** a wrong path fails in the guard spec or at the read, with the
  path in the message, instead of reading as unset. Symbol/String handling
  disappears from readers.
- **Risk:** a required read inside a broad `rescue` can turn a missing path
  into that rescue's fallback rather than an error. A section read into a
  variable is checked by `get` only down to the path given; reads below it
  rely on StrictKeys in tests, and only on code paths the tests run. The
  same broad `rescue` also catches StrictKeys' error in a test, so the test
  sees the fallback instead of the error.

## Related

- [ADR-027](adr-027-one-authority-per-value.md): every default has one
  authoritative definition; call-site defaults that repeat the defaults file
  remain to be removed.
- [ADR-030](adr-030-config-layering-by-scope.md): how config layers are
  sourced.
