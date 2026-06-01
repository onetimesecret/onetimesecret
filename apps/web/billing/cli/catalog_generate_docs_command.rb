# apps/web/billing/cli/catalog_generate_docs_command.rb
#
# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require_relative 'helpers'
require_relative '../config'

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
        output_path  = output || File.join('apps', 'web', 'billing', 'docs', 'plan-definitions.md')

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

        markdown = generate_markdown(catalog, entitlements)

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, markdown)

        puts "✅ Documentation generated: #{output_path}"
        puts "   #{markdown.lines.count} lines, #{markdown.bytesize} bytes"
      rescue Psych::SyntaxError => ex
        puts "❌ YAML syntax error: #{ex.message}"
      rescue StandardError => ex
        puts "❌ Error generating docs: #{ex.message}"
        puts ex.backtrace.first(5).join("\n") if OT.debug?
      end

      private

      def generate_markdown(catalog, entitlements)
        parts = []

        parts << generate_header(catalog)
        parts << generate_entitlements_section(entitlements) if entitlements&.any?
        parts << generate_plans_overview_table(catalog)
        parts << generate_plan_details(catalog, entitlements)
        parts << generate_stripe_metadata_section(catalog)
        parts << generate_validation_section

        parts.join("\n\n")
      end

      def generate_entitlements_section(entitlements)
        parts = ['## Entitlement Definitions', '']
        parts << 'Entitlements define features/permissions available in the billing system.'
        parts << 'Loaded from `etc/billing.yaml`.'
        parts << ''

        # Group by category
        categories = entitlements.values.map { |ent| ent['category'] }.uniq.sort

        categories.each do |category|
          ents_in_category = entitlements.select { |_id, ent| ent['category'] == category }
          next if ents_in_category.empty?

          parts << "### #{category.capitalize}"
          parts << ''

          ents_in_category.each do |ent_id, ent_data|
            parts << "- **`#{ent_id}`**: #{ent_data['description']}"
          end

          parts << ''
        end

        parts.join("\n")
      end

      def generate_header(catalog)
        # No timestamp — it caused a false git diff on every `pnpm dev`.
        <<~MD
          # Plan Catalog Reference

          **Auto-generated from:** `etc/billing.yaml`
          **Schema Version:** #{catalog['schema_version']}

          ⚠️ **Do not edit this file directly.** This file is regenerated automatically:
          - Every `pnpm dev` (via the `predev` hook)
          - On demand: `pnpm run docs:billing:generate` or `bin/ots billing catalog generate-docs`

          Source of truth is `etc/billing.yaml`. Edit that file, then any of the
          above will refresh this doc. Stale committed output is treated as a
          drift bug — keep it synchronized.

          ## Overview

          This document describes the billing plan structure and entitlements for Onetime Secret. Plan definitions are stored in Stripe product metadata and cached in Redis via `Billing::Plan`.
        MD
      end

      def generate_plans_overview_table(catalog)
        plans = catalog['plans'] || {}

        rows = []
        rows << '## Plans Overview'
        rows << ''
        rows << '| Plan ID | Name | Tier | Tenancy | Region | Display Order | On Plans Page | Legacy |'
        rows << '|---------|------|------|---------|--------|---------------|---------------|--------|'

        plans.each do |plan_id, plan_data|
          show_icon   = plan_data['show_on_plans_page'] ? '✓' : '✗'
          legacy_icon = plan_data['legacy'] ? '⚠️' : ''
          rows << format(
            '| %s | %s | %s | %s | %s | %s | %s | %s |',
            plan_id,
            plan_data['name'],
            plan_data['tier'],
            plan_data['tenancy'],
            plan_data['region'],
            plan_data['display_order'],
            show_icon,
            legacy_icon,
          )
        end

        rows.join("\n")
      end

      def generate_plan_details(catalog, entitlements)
        plans            = catalog['plans'] || {}
        default_currency = catalog['currency'] || 'cad'

        sections = ['## Plan Details', '']

        plans.each do |plan_id, plan_data|
          sections << generate_plan_section(plan_id, plan_data, entitlements, default_currency)
          sections << ''
          sections << '---'
          sections << ''
        end

        sections.join("\n")
      end

      def generate_plan_section(plan_id, plan_data, _entitlements, default_currency)
        parts = []

        # Header with legacy badge
        legacy_badge = plan_data['legacy'] ? ' ⚠️ **(Legacy)**' : ''
        parts << "### #{plan_data['name']} (`#{plan_id}`)#{legacy_badge}"
        parts << ''
        parts << plan_data['description'] if plan_data['description']
        parts << ''

        # Legacy info
        if plan_data['legacy'] && plan_data['grandfathered_until']
          parts << "**Grandfathered Until:** #{plan_data['grandfathered_until']}"
          parts << ''
        end

        # Metadata
        parts << "**Tier:** #{plan_data['tier'] || 'N/A'}"
        parts << "**Tenancy:** #{plan_data['tenancy'] || 'N/A'}"
        parts << "**Region:** #{plan_data['region'] || 'N/A'}"
        parts << ''

        # Entitlements
        if plan_data['entitlements']&.any?
          parts << '**Entitlements:**'
          plan_data['entitlements'].each do |ent|
            parts << "- `#{ent}`"
          end
          parts << ''
        end

        # Limits table
        if plan_data['limits']&.any?
          parts << '**Limits:**'
          parts << ''
          parts << '| Resource | Limit | Notes |'
          parts << '|----------|-------|-------|'

          plan_data['limits'].each do |resource, value|
            formatted_value = format_limit_value(value)
            notes           = limit_notes(resource, value)
            parts << "| #{resource} | #{formatted_value} | #{notes} |"
          end
          parts << ''
        end

        parts.concat(generate_pricing_section(plan_id, plan_data, default_currency))

        parts.join("\n")
      end

      def generate_pricing_section(plan_id, plan_data, default_currency)
        return ['**Pricing:** Free'] if plan_id == 'free_v1'
        return [] unless plan_data['prices']&.any?

        lines = ['**Pricing:**']
        plan_data['prices'].each do |price|
          amount_dollars = (price['amount'] / 100.0).round(2)
          currency_upper = (price['currency'] || default_currency).upcase
          interval_label = price['interval'] == 'month' ? 'Monthly' : 'Annual'
          lines << "- #{interval_label}: $#{amount_dollars} #{currency_upper}"
        end
        lines
      end

      def format_limit_value(value)
        case value
        when -1
          '∞ (unlimited)'
        when nil
          'TBD'
        else
          value.to_s
        end
      end

      # Per-resource note formatters keyed by Billing::Metadata::LIMIT_FIELDS value.
      # When adding a new limit, add a formatter here only if it needs a contextual
      # note; otherwise the default (empty string) is fine and renders nothing.
      # Values are coerced with to_i so YAML/CLI string inputs work uniformly, and
      # negative sentinels (-1 = unlimited) are skipped rather than rendered.
      LIMIT_NOTE_FORMATTERS = {
        'secret_lifetime' => ->(value) { value && value.to_i > 0 ? "#{value.to_i / 86_400} days" : '' },
        'teams' => ->(value) { value&.to_i == 0 ? 'No team access' : '' },
        'total_members_per_org' => ->(value) { value&.to_i == 1 ? 'Individual only' : '' },
      }.freeze
      private_constant :LIMIT_NOTE_FORMATTERS

      def limit_notes(resource, value)
        formatter = LIMIT_NOTE_FORMATTERS[resource]
        formatter ? formatter.call(value) : ''
      end

      def generate_stripe_metadata_section(catalog)
        schema = catalog['stripe_metadata_schema'] || {}

        parts = ['## Stripe Product Configuration', '']
        parts << 'Each Stripe product must include specific metadata fields to be recognized by the billing system.'
        parts << ''

        if schema['required']
          parts << '### Required Metadata Fields'
          parts << ''
          parts << '```json'
          parts << '{'

          schema['required'].each_with_index do |entry, idx|
            # YAML loads each entry as a single-key Hash; pull the kv pair out
            # explicitly rather than relying on destructuring (which would bind
            # `key` to the whole Hash and emit malformed JSON).
            key, desc = entry.is_a?(Hash) ? entry.first : [entry, '']
            comma     = idx < schema['required'].size - 1 ? ',' : ''
            parts << "  \"#{key}\": \"#{desc}\"#{comma}"
          end

          parts << '}'
          parts << '```'
          parts << ''
        end

        if schema['optional']
          parts << '### Optional Metadata Fields'
          parts << ''
          parts << '```json'
          parts << '{'

          schema['optional'].each_with_index do |entry, idx|
            key, desc = entry.is_a?(Hash) ? entry.first : [entry, '']
            comma     = idx < schema['optional'].size - 1 ? ',' : ''
            parts << "  \"#{key}\": \"#{desc}\"#{comma}"
          end

          parts << '}'
          parts << '```'
        end

        parts.join("\n")
      end

      def generate_validation_section
        <<~MD
          ## Validation and Sync

          ### Validate Catalog Structure

          Validate YAML structure and compare with Stripe:

          ```bash
          bin/ots billing catalog validate
          bin/ots billing catalog validate --catalog-only  # Skip Stripe comparison
          bin/ots billing catalog validate --strict        # Fail on warnings
          ```

          ### Sync Plans from Stripe

          After configuring products in Stripe, sync to local Redis cache:

          ```bash
          bin/ots billing sync
          bin/ots billing sync --clear  # Clear cache first
          ```

          Only products with all required metadata fields, at least one recurring price, and `app: "onetimesecret"` will be synced.

          ### View Cached Plans

          ```bash
          bin/ots billing plans
          ```

          ## Setup Workflow

          1. **Edit catalog:** Modify `etc/billing.yaml`
          2. **Validate:** `bin/ots billing catalog validate --catalog-only`
          3. **Create/update in Stripe:** `./scripts/setup_stripe_plans.sh --update`
          4. **Verify in Stripe:** Check Stripe Dashboard
          5. **Sync to cache:** `bin/ots billing sync`
          6. **Update docs:** `bin/ots billing catalog generate-docs`
          7. **Commit:** Commit both YAML and generated docs
        MD
      end
    end
  end
end

Onetime::CLI.register 'billing catalog generate-docs', Onetime::CLI::BillingCatalogGenerateDocsCommand
