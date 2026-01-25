# apps/web/billing/cli/catalog_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Manage the billing plan catalog
    class BillingCatalogCommand < Command
      include BillingHelpers

      desc 'Manage the billing plan catalog'

      def call(**)
        puts <<~HELP
          Manage the billing plan catalog including validation,
          synchronization with Stripe, and documentation generation.

          Available subcommands:
            push          - Push catalog to Stripe (create/update products)
            pull          - Pull from Stripe to Redis cache
            validate      - Validate catalog YAML structure and Stripe consistency
            generate-docs - Generate Markdown documentation from the catalog

          Examples:
            bin/ots billing catalog                    # Show this help
            bin/ots billing catalog push --dry-run    # Preview changes to Stripe
            bin/ots billing catalog push              # Push catalog to Stripe
            bin/ots billing catalog pull              # Sync Stripe to Redis
            bin/ots billing catalog validate          # Validate catalog and Stripe sync
            bin/ots billing catalog generate-docs     # Generate catalog documentation

          Use 'bin/ots billing catalog SUBCOMMAND --help' for more information.
        HELP
      end
    end
  end
end

Onetime::CLI.register 'billing catalog', Onetime::CLI::BillingCatalogCommand
