# lib/onetime/cli/write_gate.rb
#
# frozen_string_literal: true

# The write gate shared by every `bin/ots` verb that changes state.
#
# A verb that includes this module is a DRY RUN unless --apply is given. There
# is no confirmation prompt: the bare run is the preview, and --apply is the
# only way to write. `-y`, `--yes` and `-f` are aliases for --apply so a script
# written against an earlier prompt-skipping flag still writes. The exception
# is a verb whose old prompt skip never wrote on its own (a bare `--yes` was a
# preview): it passes `aliases: []` and keeps the old flag as a no-op, so the
# same invocation still previews. --dry-run only states the default, so passing
# it with --apply is an error rather than a guess about which flag the operator
# meant.
#
#   class OrgDeleteCommand < Command
#     include WriteGate
#
#     write_gate_options 'Delete the organization'
#
#     def call(org:, apply: false, dry_run: false, json: false, **)
#       dry_run = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
#       ...
#       if result.status == :planned
#         dry_run_header
#         print_plan(result)
#         dry_run_footer('delete')
#       end
#     end
#   end
#
# Every dry run reads the same way: the header line first, the plan, and the
# footer naming the flag that applies it. Operators learn it once; `grep` finds
# every occurrence.
#
# A piped confirmation (`echo y | bin/ots …`) is not an apply. The run is a
# dry run and exits 0 like any other preview, so a script that relied on the
# prompt must pass --apply.
#
# This module owns the gate only. Resolution helpers (`resolve_org`,
# `resolve_domain`, …) and `error_exit` stay in the per-area Shared modules.
require 'json'

module Onetime
  module CLI
    module WriteGate
      # Aliases for --apply. `-y`/`--yes` are the prompt-skipping spellings
      # these verbs accepted before the gate; `-f` was `--force` on a few.
      APPLY_ALIASES = ['-y', '--yes', '-f'].freeze

      DRY_RUN_HEADER = 'DRY RUN — nothing was written'

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare --apply (with its aliases) and --dry-run on the command, in
        # that order, where the call is made.
        #
        # @param verb [String] what --apply does, e.g. 'Delete the organization'
        # @param aliases [Array<String>] every alias of --apply. A verb narrows
        #   APPLY_ALIASES when it uses one of them for something else (`-f` for
        #   `--file`), extends it for a flag it accepted before the gate
        #   (`--run`), and passes [] when its old `-y`/`--yes`/`-f` only skipped
        #   a prompt that --apply also needed: a bare `--yes` was a preview
        #   there, and an alias would turn it into a write.
        def write_gate_options(verb, aliases: APPLY_ALIASES)
          option :apply,
            type: :boolean,
            default: false,
            aliases: aliases,
            desc: "#{verb} (default: dry run, nothing written)"
          option :dry_run,
            type: :boolean,
            default: false,
            desc: 'Preview only (the default; contradicts --apply)'
        end
      end

      # The gate. Call it first in `call`, before anything is resolved.
      #
      # @return [Boolean] true for a dry run
      def dry_run_unless_applied(apply:, dry_run:, json:)
        if apply && dry_run
          message = '--apply and --dry-run are contradictory; pass one or neither'
          puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
          exit 1
        end

        !apply
      end

      # First line of every dry-run report.
      def dry_run_header
        puts DRY_RUN_HEADER
      end

      # Last line of a dry-run report that has something to apply. Omit it when
      # the preview found nothing to write: --apply would change nothing.
      #
      # @param verb [String] completes "Re-run with --apply to …"
      def dry_run_footer(verb = 'write')
        puts "Re-run with --apply to #{verb}."
      end
    end
  end
end
