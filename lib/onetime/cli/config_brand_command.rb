# lib/onetime/cli/config_brand_command.rb
#
# frozen_string_literal: true

# Diagnose brand-pack resolution for the v0.26.0 neutral-branding incident
# (#3822): byte-identical brand files rendered correctly on CA/NZ but fell back
# to neutral on UK. Ops runs this on each region and diffs the output (prefer
# `--json`) to find which of three otherwise-indistinguishable modes is in play:
# config divergence, env not reaching the container, or a boot-time mount race.
#
# This command is a THIN ADAPTER: all resolution logic lives in
# `Onetime.brand_pack_diagnostics` (read-only, single source of truth). Here we
# only boot, call it, format, and set a deploy-gate exit code.
#
# Exit codes (both human and --json modes):
#   2  resolved_dir is nil        -> broken checkout, default pack itself missing
#   1  fell_back_to_default OR boot_vs_live_mismatch -> serving wrong/neutral branding
#   0  otherwise

require 'json'

module Onetime
  module CLI
    # `bin/ots config brand` — prints brand-pack resolution diagnostics.
    class ConfigBrandCommand < Command
      desc 'Diagnose brand-pack resolution (#3822 neutral-branding incident)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Machine-parseable JSON for fleet diffing (stable key order)'

      # Width of the label column (incl. trailing colon) in human output.
      LABEL_WIDTH = 24
      # Indent for continuation lines, aligning under the value column.
      CONT_INDENT = (' ' * (LABEL_WIDTH + 2)).freeze

      def call(json: false, **)
        diagnostics = collect(json: json)

        if json
          puts JSON.pretty_generate(diagnostics)
        else
          print_human(diagnostics)
        end

        exit exit_code_for(diagnostics)
      end

      private

      # Boot (the diagnostic reads OT.conf, nil unless booted) then gather the
      # payload. In --json mode both steps must be shielded: SemanticLogger's
      # appender writes to $stdout (setup_loggers.rb) and the resolver itself
      # (brand_overlay_dir) logs a fallback warning to $stdout on the very path
      # this tool exists to detect. The fleet-diff pipe parses stdout, so any
      # such line would corrupt the JSON document.
      def collect(json:)
        return boot_and_diagnose unless json

        with_stdout_diverted_to_stderr { boot_and_diagnose }
      end

      def boot_and_diagnose
        boot_application!
        Onetime.brand_pack_diagnostics
      end

      # Redirect fd 1 to stderr for the duration of the block, flushing the async
      # log appender before restoring so queued boot lines land on stderr, not in
      # front of the JSON. fd-level (not $stdout=) so it also catches STDOUT.puts.
      def with_stdout_diverted_to_stderr
        saved = $stdout.dup
        $stdout.reopen($stderr)
        yield
      ensure
        SemanticLogger.flush if defined?(SemanticLogger)
        if saved
          $stdout.reopen(saved)
          saved.close
        end
      end

      # Deploy-gate semantics. resolved_dir nil (broken checkout) is the most
      # severe and takes precedence over the serving-wrong-branding signals.
      def exit_code_for(diagnostics)
        return 2 if diagnostics['resolved_dir'].nil?
        return 1 if diagnostics['fell_back_to_default'] || diagnostics['boot_vs_live_mismatch']

        0
      end

      # Human-readable summary. Field order is stable so ops can eyeball-diff the
      # same rows across regions; the two danger booleans are called out loudly.
      def print_human(diagnostics)
        puts 'Brand pack diagnostics'
        print_sources(diagnostics)
        row 'resolved_dir', or_none(diagnostics['resolved_dir'])
        print_flags(diagnostics)
        print_manifest(diagnostics['manifest'] || {})
        row 'brand_absorbed (boot)', list_or_none((diagnostics['config'] || {})['brand_absorbed'])
        print_roots(diagnostics['roots'])
        row 'overlay_assets', list_or_none(diagnostics['overlay_assets'])
      end

      def print_sources(diagnostics)
        row 'home', or_none(diagnostics['home'])
        row 'env', env_line(diagnostics['env'] || {})
        row 'config (boot snapshot)', config_line(diagnostics['config'] || {})
      end

      def env_line(env)
        "BRAND_PACK=#{or_unset(env['brand_pack'])}   " \
          "BRAND_ASSETS_DIR=#{or_unset(env['brand_assets_dir'])}"
      end

      def config_line(config)
        "brand_pack=#{or_unset(config['brand_pack'])}   " \
          "brand_assets_dir=#{or_unset(config['brand_assets_dir'])}"
      end

      def print_flags(diagnostics)
        row 'fell_back_to_default',
          danger(diagnostics['fell_back_to_default'], 'serving neutral/default')
        row 'boot_vs_live_mismatch',
          danger(diagnostics['boot_vs_live_mismatch'], 'boot ran before the pack mounted; restart')
      end

      def print_manifest(manifest)
        row 'manifest', manifest_line(manifest)
        cont "keys_on_disk:   #{list_or_none(manifest['keys_on_disk'])}"
      end

      def manifest_line(manifest)
        path = manifest['path']
        return '(none)' if path.nil?

        "#{path}  #{manifest['exists'] ? '(exists)' : '(missing)'}"
      end

      def print_roots(roots)
        roots = Array(roots)
        return row('roots', '(none)') if roots.empty?

        first, *rest = roots
        row 'roots', root_line(first)
        rest.each { |root| cont root_line(root) }
      end

      def root_line(root)
        "#{root['exists'] ? '[x]' : '[ ]'} #{root['path']}"
      end

      # Row + continuation-line emitters -------------------------------------

      def row(label, value)
        puts "  #{"#{label}:".ljust(LABEL_WIDTH)}#{value}"
      end

      def cont(value)
        puts "#{CONT_INDENT}#{value}"
      end

      # Null/empty-safe formatters -------------------------------------------

      def danger(flag, note)
        flag ? "YES  <- #{note}" : 'NO'
      end

      # ENV/config scalars: absent -> (unset).
      def or_unset(value)
        value.to_s.strip.empty? ? '(unset)' : value.to_s
      end

      # Path scalars: nil -> (none). resolved_dir/manifest path can be nil.
      def or_none(value)
        value.nil? ? '(none)' : value.to_s
      end

      def list_or_none(list)
        Array(list).empty? ? '(none)' : Array(list).join(', ')
      end
    end
  end
end

Onetime::CLI.register 'config brand', Onetime::CLI::ConfigBrandCommand
