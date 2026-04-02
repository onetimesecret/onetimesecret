# apps/web/billing/cli/diagnose_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Diagnose entitlement resolution for a specific user
    #
    # Walks the full chain: email → customer → org → planid → plan cache →
    # billing.yaml fallback → entitlements. Reports the first break point found.
    #
    # Usage:
    #   bin/ots billing diagnose user@example.com
    #   bin/ots billing diagnose user@example.com --entitlement custom_mail_sender
    #   bin/ots billing diagnose user@example.com --verbose
    #
    class BillingDiagnoseCommand < Command
      include BillingHelpers

      desc 'Diagnose entitlement resolution for a user'

      argument :email, required: true, desc: 'Customer email address'

      option :entitlement,
        type: :string,
        default: nil,
        desc: 'Check a specific entitlement (e.g., custom_mail_sender)'

      option :verbose,
        type: :boolean,
        default: false,
        desc: 'Show all resolution details even when passing'

      def call(email:, entitlement: nil, verbose: false, **)
        boot_application!

        puts "Diagnosing: #{email}"
        puts '=' * 70
        puts

        # Step 1: Billing enabled?
        billing_on = check_billing_enabled(verbose)

        # Step 2: Customer lookup
        customer = check_customer(email)
        return unless customer

        # Step 3: Organization lookup
        org = check_organization(customer)
        return unless org

        # Step 4: Plan assignment
        planid = check_planid(org, verbose)

        # Step 5: Plan resolution (cache vs config fallback)
        resolved_entitlements = check_plan_resolution(org, planid, billing_on, verbose)

        # Step 6: Feature flags (for sender-specific checks)
        if entitlement == 'custom_mail_sender'
          check_custom_mail_feature_flag
        end

        # Step 7: Entitlement check
        puts 'ENTITLEMENTS'
        puts '-' * 70
        if resolved_entitlements.empty?
          puts '  (none)'
        else
          resolved_entitlements.sort.each do |ent|
            marker = entitlement && ent == entitlement ? ' <--' : ''
            puts "  #{ent}#{marker}"
          end
        end
        puts

        return unless entitlement

        has_it = resolved_entitlements.include?(entitlement)
        label  = has_it ? 'YES' : 'NO'
        puts "Result: org.can?('#{entitlement}') => #{label}"
        return if has_it

        puts
        puts 'Possible fixes:'
        suggest_fixes(entitlement, planid, billing_on, org)
      end

      private

      def check_billing_enabled(verbose)
        billing_on = Onetime::BillingConfig.instance.enabled?
        status     = billing_on ? 'enabled' : 'disabled (standalone mode)'
        puts "Billing: #{status}"

        unless billing_on
          puts '  -> STANDALONE_ENTITLEMENTS apply (full access)'
          puts
        end

        if verbose && billing_on
          puts "  Stripe key: #{OT.billing_config.stripe_key.to_s.empty? ? 'not configured' : 'configured'}"
          puts
        end

        billing_on
      rescue StandardError => ex
        puts "Billing: ERROR - #{ex.message}"
        puts '  -> Treated as disabled (standalone mode, full access)'
        puts
        false
      end

      def check_customer(email)
        puts 'CUSTOMER'
        puts '-' * 70

        # Try loading by custid (which is the email)
        customer = Onetime::Customer.load(email)
        unless customer
          puts "  NOT FOUND: No customer record for '#{email}'"
          puts "  Fix: Create with 'bin/ots customers --create #{email}'"
          puts
          return nil
        end

        puts "  Email:    #{customer.email || customer.custid}"
        puts "  Role:     #{customer.role}"
        puts "  Verified: #{customer.verified}"
        puts "  ExtID:    #{customer.extid}"
        puts

        customer
      end

      def check_organization(customer)
        puts 'ORGANIZATION'
        puts '-' * 70

        # Use organization_ids (shallow) to get the count without hydrating
        # all orgs. Each organization_instances.to_a call does HGETALL per org,
        # which is O(N) Redis calls for N memberships. Instead, load orgs
        # individually and stop once we find the default.
        org_ids = customer.organization_ids
        if org_ids.empty?
          puts '  NOT FOUND: Customer has no organizations'
          puts '  Fix: Organization should be auto-created on account setup'
          puts
          return nil
        end

        # Find the default org by loading one at a time, stopping early.
        # Typical customer has 1 org so this is a single HGETALL.
        org       = nil
        first_org = nil
        org_ids.each do |oid|
          loaded = Onetime::Organization.load(oid)
          next unless loaded

          first_org ||= loaded
          if loaded.is_default
            org = loaded
            break
          end
        end
        org     ||= first_org

        unless org
          puts '  NOT FOUND: Organization IDs exist but none could be loaded'
          puts
          return nil
        end

        puts "  Org ID:       #{org.objid}"
        puts "  Display Name: #{org.display_name}" if org.respond_to?(:display_name)
        puts "  Is Default:   #{org.is_default}"
        puts "  Org Count:    #{org_ids.size}"

        # Stripe fields
        stripe_cust = org.respond_to?(:stripe_customer_id) ? org.stripe_customer_id : nil
        stripe_sub  = org.respond_to?(:stripe_subscription_id) ? org.stripe_subscription_id : nil
        puts "  Stripe Customer:     #{stripe_cust.to_s.empty? ? '(none)' : stripe_cust}"
        puts "  Stripe Subscription: #{stripe_sub.to_s.empty? ? '(none)' : stripe_sub}"
        puts

        org
      end

      def check_planid(org, _verbose)
        puts 'PLAN ASSIGNMENT'
        puts '-' * 70

        planid = org.planid.to_s
        if planid.empty?
          puts '  Plan ID: (empty)'
          puts '  -> Will use FREE_TIER_ENTITLEMENTS'
        else
          puts "  Plan ID: #{planid}"
        end
        puts

        planid
      end

      def check_plan_resolution(_org, planid, billing_on, verbose)
        puts 'PLAN RESOLUTION'
        puts '-' * 70

        unless billing_on
          ents = Onetime::Models::Features::WithEntitlements::STANDALONE_ENTITLEMENTS.dup
          puts '  Source: STANDALONE_ENTITLEMENTS (billing disabled)'
          puts "  Count:  #{ents.size}"
          puts
          return ents
        end

        if planid.empty?
          ents = Onetime::Models::Features::WithEntitlements::FREE_TIER_ENTITLEMENTS.dup
          puts '  Source: FREE_TIER_ENTITLEMENTS (no plan assigned)'
          puts "  Count:  #{ents.size}"
          puts
          return ents
        end

        # Try Redis cache
        plan = ::Billing::Plan.load(planid)
        if plan
          ents = plan.entitlements.to_a
          puts '  Source: Redis plan cache'
          puts "  Key:    billing_plan:#{planid}:entitlements"
          puts "  Count:  #{ents.size}"
          if verbose && plan.respond_to?(:tier)
            puts "  Tier:   #{plan.tier}"
          end
          puts
          return ents
        end

        puts "  Redis cache: MISS for '#{planid}'"

        # Try billing.yaml fallback
        config_plan = ::Billing::Plan.load_from_config(planid)
        if config_plan && config_plan[:entitlements]
          ents    = config_plan[:entitlements].dup
          puts '  Source: billing.yaml config fallback'
          base_id = planid.sub(/_(month|year)ly$/, '')
          puts "  Config key: #{base_id}"
          puts "  Count:  #{ents.size}"
          puts
          return ents
        end

        puts "  billing.yaml: MISS for '#{planid}'"

        # Final fallback
        ents = Onetime::Models::Features::WithEntitlements::FREE_TIER_ENTITLEMENTS.dup
        puts '  Source: FREE_TIER_ENTITLEMENTS (final fallback)'
        puts "  Count:  #{ents.size}"
        puts
        ents
      end

      def check_custom_mail_feature_flag
        puts 'FEATURE FLAGS'
        puts '-' * 70

        flag   = OT.conf&.dig('features', 'organizations', 'custom_mail_enabled')
        status = flag ? 'true' : "#{flag.inspect} (will block API requests)"
        puts "  features.organizations.custom_mail_enabled: #{status}"
        puts
      end

      def suggest_fixes(entitlement, planid, billing_on, _org)
        if billing_on && planid.empty?
          puts '  1. Org has no plan. Assign a subscription via Stripe or set planid directly.'
          puts '  2. Or run: bin/ots billing catalog pull --clear'
        elsif billing_on && !planid.empty?
          puts "  1. Verify '#{entitlement}' is in billing.yaml under the plan's entitlements list"
          puts '  2. Run: bin/ots billing catalog push   (sync YAML -> Stripe metadata)'
          puts '  3. Run: bin/ots billing catalog pull    (sync Stripe -> Redis cache)'
          puts "  4. Check Stripe product metadata has '#{entitlement}' in the entitlements field"
        elsif !billing_on
          puts '  Billing is disabled — STANDALONE_ENTITLEMENTS should include everything.'
          puts "  If '#{entitlement}' is missing from STANDALONE_ENTITLEMENTS, add it in:"
          puts '    lib/onetime/models/features/with_entitlements.rb'
        end
      end
    end
  end
end

Onetime::CLI.register 'billing diagnose', Onetime::CLI::BillingDiagnoseCommand
