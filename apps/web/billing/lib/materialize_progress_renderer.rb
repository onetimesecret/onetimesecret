# apps/web/billing/lib/materialize_progress_renderer.rb
#
# frozen_string_literal: true

module Billing
  # Renders MaterializePlans streaming events to stdout.
  #
  # Three verbosity modes:
  #   :default — one line per org (the audit-log baseline)
  #   :verbose — :default plus one line per membership under each cascade
  #   :quiet   — no per-org output (caller handles banner and summary)
  #
  # Decoupled from the operation so CLI commands, background jobs, and
  # future UIs can plug in their own renderers. The +indent+ parameter
  # lets callers control nesting depth (e.g., standalone command vs.
  # step inside a composite command).
  #
  class MaterializeProgressRenderer
    # @param total [Integer] Total orgs to scan (for progress counter)
    # @param verbosity [:default, :verbose, :quiet]
    # @param include_memberships [Boolean] Whether cascade is enabled
    # @param indent [Integer] Leading spaces for progress lines (detail lines add 4 more)
    def initialize(total:, verbosity: :default, include_memberships: false, indent: 2)
      @total               = total
      @verbosity           = verbosity
      @include_memberships = include_memberships
      @prefix              = ' ' * indent
      @detail_prefix       = ' ' * (indent + 4)
      @processed           = 0
    end

    def render(event)
      @processed += 1
      return if @verbosity == :quiet

      puts "#{@prefix}[#{@processed}/#{@total}] #{describe(event)}"
      render_membership_detail(event) if @verbosity == :verbose
    end

    private

    def render_membership_detail(event)
      details = event.cascade && event.cascade[:details]
      return if details.nil? || details.empty?

      details.each do |m|
        puts "#{@detail_prefix}↳ #{format_membership(m)}"
      end
    end

    def format_membership(detail)
      role = detail[:role]
      if detail[:status] == :ok
        "#{detail[:objid]} (role=#{role}, plan=#{detail[:planid]}): " \
          "#{detail[:entitlements_count]} entitlements"
      else
        "#{detail[:objid]} (role=#{role}): FAILED — #{detail[:error]}"
      end
    end

    def describe(event)
      case event.event
      when :materialized
        cascade = event.cascade ? " + cascaded #{event.cascade[:success]}/#{event.cascade[:total]} memberships" : ''
        "Materialized: #{event.org_extid} (#{event.planid}, #{event.entitlements_count} entitlements)#{cascade}"
      when :would_materialize
        cascade_hint = @include_memberships ? ' (+memberships cascade)' : ''
        "Would materialize: #{event.org_extid} (#{event.planid}, #{event.entitlements_count} entitlements)#{cascade_hint}"
      when :skipped_plan_filter
        "Skipping (plan filter): #{event.org_extid}"
      when :skipped_no_plan
        "Skipping (no planid): #{event.org_extid}"
      when :failed_plan_not_found
        "Error: #{event.reason} (#{event.org_extid})"
      when :failed_org_write
        "Error: org write failed for #{event.org_extid}: #{event.reason}"
      when :failed_cascade
        cascade = event.cascade ? " (#{event.cascade[:success]}/#{event.cascade[:total]} succeeded)" : ''
        "Error: cascade failed for #{event.org_extid}: #{event.reason}#{cascade}"
      else
        "[#{event.event}] #{event.org_extid}"
      end
    end
  end
end
