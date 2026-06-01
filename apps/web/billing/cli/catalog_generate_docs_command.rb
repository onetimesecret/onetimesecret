# apps/web/billing/cli/catalog_generate_docs_command.rb
#
# frozen_string_literal: true

require_relative '../docs_renderer'

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
    # The wrapper script (scripts/billing-docs-generate.sh) calls the
    # standalone scripts/billing-docs-generate.rb directly to avoid
    # loading the full app stack. This CLI subcommand is kept for
    # backward compatibility.
    #
    # If `etc/billing.yaml` is absent (the common case for fresh checkouts
    # without a configured Stripe catalog), the command exits cleanly with
    # an informational line — it is NOT an error.
    class BillingCatalogGenerateDocsCommand < DelayBootCommand

      desc 'Generate plan-definitions.md from billing.yaml'

      option :output,
        type: :string,
        desc: 'Output file path (default: apps/web/billing/docs/plan-definitions.md)'

      def call(output: nil, **)
        kwargs = {}
        kwargs[:output_path] = output if output

        Billing::DocsRenderer.generate_and_write(**kwargs)
      rescue Psych::SyntaxError => ex
        raise "YAML syntax error in billing config: #{ex.message}"
      rescue StandardError => ex
        raise "Error generating billing docs: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing catalog generate-docs', Onetime::CLI::BillingCatalogGenerateDocsCommand
