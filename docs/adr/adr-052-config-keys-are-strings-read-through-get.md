---
id: "052"
status: accepted
title: "ADR-052: Config Keys Are Strings, and Code Reads Config Through get"
---

## Status

Accepted

## Date

2026-11-26

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
2. **Code reads a setting through `OT.conf.get(path[, default])`, with the
   whole path.** This covers `lib/`, `apps/` and the tests. The path is
   dotted (`'site.admin.elevation.window'`), or an Array of Strings when a
   segment is a variable. Without a default the setting is required: a path
   that is not in the config raises `MissingPathError` with the path, and a
   value an operator sets to nil reads as nil. With a default the setting
   is optional. A positional default applies to missing keys and nil values.
   A block supplies a fallback only when a key is absent. The boot banner
   uses this distinction because an explicit nil disables a section there.
   `false` and `0` are values and are never replaced by the
   default. A path that runs through a value that is neither a Hash nor
   nil raises `PathTypeError`, with or without a default; a nil section on
   the way reads as unset. Code does not read a setting out of a section
   that `get` returned (`OT.conf.get('site.admin')['window']`); it may
   iterate, copy or serialize a section as a whole. A method that needs a
   setting reads it with `get`; it does not take the config, or a section
   of it, as an argument for tests to replace. Tests stub or change
   `OT.conf` instead.
3. **A spec enforces both.** `spec/unit/onetime/config/access_guard_spec.rb`
   parses `lib/` and `apps/` with Prism. It fails on any use of `OT.conf`
   other than `.get` that is not listed with a reason, on a read into a
   section that `get` returned (followed through locals, instance
   variables, methods, attr_readers and RSpec lets in the same file), on a
   required path the shipped config does not have, and on an optional path
   that is not listed in `OPTIONAL_PATHS` with the reason it can be absent.
   In the tests it fails on a read of `OT.conf` other than `get` and on a
   read into a section. In test runs, `Onetime::Config::StrictKeys` makes
   every Hash in the config tree raise on a non-String key.

A dotted path needs one key type, and Strings are what YAML and the
defaults file produce. Raising on a missing required path follows
`Hash#fetch` and `ENV.fetch`: the caller states whether a value may be
absent, and the guard can check that statement against the shipped config
before the code runs.

`OT.conf` stays a Hash with `get` added to the root instance, so tests and
tools can still write, copy and serialize it as a Hash
(`OT.conf.get('site')['host'] = 'example.com'`). Outside test runs the
sections below the root are plain Hashes.

## Trade-offs

- **We lose:** the freedom to read config with the Hash API, and config
  arguments as a test seam. Each optional setting that the defaults file
  does not define needs an `OPTIONAL_PATHS` entry.
- **We gain:** grepping a dotted path finds every reader of that setting. A
  wrong path fails in the guard spec or at the read, with the path in the
  message, instead of reading as unset. Symbol/String handling disappears
  from readers.
- **Risk:** a required read inside a broad `rescue` can turn a missing path
  into that rescue's fallback rather than an error. The guard follows a
  section within one file; a section passed as an argument to a method or
  yielded to a block is not followed, so a read of it relies on review and
  on StrictKeys in tests. The same broad `rescue` also catches StrictKeys' error in a test,
  so the test sees the fallback instead of the error.

## Related

- [ADR-027](adr-027-one-authority-per-value.md): every default has one
  authoritative definition; call-site defaults that repeat the defaults file
  remain to be removed.
- [ADR-030](adr-030-config-layering-by-scope.md): how config layers are
  sourced.

## Implementation Notes

### Accepted and implemented (2026-11-26)

Proposed on 2026-11-14 and accepted on 2026-11-26. The decision is
implemented on `develop` through five merge requests: !4959, !4965, !4966
and !4969 (2026-11-14), and !4975 (2026-11-22), which extended it to
section reads, config seams and the tests. Issue #3991 is closed.
