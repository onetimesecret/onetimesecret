# apps/web/billing/cli/catalog_generate_docs_command.rb
#
# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require_relative 'helpers'
require_relative '../config'
require_relative '../operations/catalog/docs_generator'

module Onetime
  module CLI
    # Generate markdown documentation from plan catalog YAML
    #
    # When this runs
    # --------------
    # Manually:           bin/ots billing catalog generate-docs
    # Via pnpm (strict):  pnpm run docs:billing:generate
    # Via pnpm (lenient): pnpm run docs:billing:generate:tolerant
    # Auto on dev:        chained from `predev` (via the tolerant variant)
    #                     so the doc refreshes once per `pnpm dev`. Not
    #                     chained into `prebuild` because the frontend-build
    #                     CI job is Node-only and the doc is committed
    #                     source, not a build artifact.
    #
    # The wrapper script (scripts/billing-docs-generate.sh) skips silently
    # when bundler isn't available, so frontend-only devs can still run
    # `pnpm dev` without Ruby. When bundler IS present but generation
    # errors, the tolerant variant emits a loud multi-line warning to
    # stderr but exits 0; the strict variant propagates the failure.
    #
    # If `etc/billing.yaml` is absent (the common case for fresh checkouts
    # without a configured Stripe catalog), the command exits cleanly with
    # an informational line — it is NOT an error.
    class BillingCatalogGenerateDocsCommand < Command
      include BillingHelpers

      desc 'Generate plan-definitions.md from billing.yaml'

      option :output,
        type: :string,
        desc: 'Output file path (default: apps/web/billing/docs/plan-definitions.md)'

      def call(output: nil, **)
        # Intentionally NOT calling boot_application!.
        #
        # This command is a pure YAML → markdown transform: it reads
        # etc/billing.yaml, runs ERB, and writes Markdown. It does not
        # touch Familia, Redis, the model layer, or auth config. Booting
        # the full app would couple this generator to a fully-provisioned
        # environment (Redis up, auth.yaml present, etc.) for no benefit,
        # which is what broke when we first wired it into `predev`.
        #
        # Keeping it boot-free means: CI can regenerate without Redis,
        # the predev hook can be strict instead of best-effort, and any
        # contributor with Ruby + a billing.yaml can refresh the doc.

        catalog_path = Billing::Config.config_path
        output_path  = output || Billing::Operations::Catalog::DocsGenerator::DEFAULT_OUTPUT_PATH

        if catalog_path.nil? || !File.exist?(catalog_path.to_s)
          # Informational, not an error: fresh checkouts and standalone
          # deployments without billing configured skip cleanly. The
          # `predev` hook depends on this graceful no-op.
          puts '[billing catalog generate-docs] skipped: billing.yaml not configured'
          return
        end

        puts "Loading catalog: #{catalog_path}"

        catalog = Billing::Config.safe_load_config

        # Load entitlements from billing.yaml
        entitlements = Billing::Config.load_entitlements
        puts "Loaded #{entitlements.size} entitlements from billing config"

        # Delegate the pure YAML → markdown transform to the boot-free
        # generator module so the same logic backs both this command and the
        # standalone scripts/generate_billing_docs.rb entrypoint.
        markdown = Billing::Operations::Catalog::DocsGenerator.write(
          catalog,
          output_path,
          entitlements: entitlements,
        )

        puts "✅ Documentation generated: #{output_path}"
        puts "   #{markdown.lines.count} lines, #{markdown.bytesize} bytes"
      rescue Psych::SyntaxError => ex
        puts "❌ YAML syntax error: #{ex.message}"
      rescue StandardError => ex
        puts "❌ Error generating docs: #{ex.message}"
        puts ex.backtrace.first(5).join("\n") if OT.debug?
      end
    end
  end
end

Onetime::CLI.register 'billing catalog generate-docs', Onetime::CLI::BillingCatalogGenerateDocsCommand
