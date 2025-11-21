# frozen_string_literal: true

module Onetime
  module CLI
    # Safety-focused helpers for billing CLI commands
    #
    # Provides standardized safety features for administrative operations:
    # - Test mode validation to prevent production accidents
    # - Dry-run mode for operation preview
    # - Consistent confirmation prompts
    # - Progress indicators for long operations
    # - Standardized success/error messaging
    #
    # ## Usage
    #
    #   class BillingCommand < Command
    #     include SafetyHelpers
    #
    #     option :dry_run, type: :boolean, default: false
    #     option :yes, type: :boolean, default: false
    #
    #     def call(dry_run: false, yes: false, **)
    #       validate_test_mode! unless production_allowed?
    #
    #       display_operation_summary('Cancel subscription', {
    #         subscription_id: 'sub_123',
    #         reason: 'customer_request'
    #       }, dry_run: dry_run)
    #
    #       return if dry_run
    #
    #       return unless confirm_operation('Cancel subscription?', auto_yes: yes)
    #
    #       # Perform operation...
    #       display_success('Subscription canceled', { id: 'sub_123' })
    #     end
    #   end
    #
    module SafetyHelpers
      # Validate that Stripe is in test mode
      #
      # Prevents accidental operations on production Stripe account.
      # Checks that API key starts with 'sk_test_'.
      #
      # @raise [RuntimeError] If not in test mode
      # @return [Boolean] True if in test mode
      #
      # @example
      #   validate_test_mode!  # Raises if production key
      #
      def validate_test_mode!
        stripe_key = Stripe.api_key || OT.billing_config.stripe_key

        if stripe_key.nil? || stripe_key.to_s.strip.empty?
          puts 'Error: Stripe API key not configured'
          return false
        end

        unless stripe_key.start_with?('sk_test_')
          puts "\n⚠️  WARNING: Production Stripe key detected!"
          puts "   Key prefix: #{stripe_key[0..10]}..."
          puts "   This operation requires a test key (sk_test_)"
          puts "\nTo run this operation:"
          puts "  1. Use a test API key, OR"
          puts "  2. Add --force flag if you really mean to use production"
          puts "\n❌ Operation aborted for safety"
          raise 'Production mode detected - operation requires test mode'
        end

        true
      end

      # Display operation summary
      #
      # Shows what operation will be performed and its parameters.
      # Adds [DRY RUN] prefix when in preview mode.
      #
      # @param operation [String] Operation description
      # @param details [Hash] Operation details to display
      # @param dry_run [Boolean] Whether this is a dry run
      # @return [void]
      #
      # @example
      #   display_operation_summary('Cancel subscription', {
      #     subscription_id: 'sub_123',
      #     cancel_at: 'period_end'
      #   }, dry_run: true)
      #
      def display_operation_summary(operation, details = {}, dry_run: false)
        prefix = dry_run ? '[DRY RUN] ' : ''
        puts "\n#{prefix}#{operation}:"

        details.each do |key, value|
          formatted_key = key.to_s.split('_').map(&:capitalize).join(' ')
          puts "  #{formatted_key}: #{value}"
        end

        puts
      end

      # Execute block with dry-run support
      #
      # Conditionally executes a block based on dry_run flag.
      # Prints notification when in dry-run mode.
      #
      # @param dry_run [Boolean] Whether to skip execution
      # @yield Block to execute if not dry run
      # @return [void]
      #
      # @example
      #   execute_with_dry_run(dry_run: options[:dry_run]) do
      #     Stripe::Subscription.cancel(subscription_id)
      #   end
      #
      def execute_with_dry_run(dry_run: false)
        if dry_run
          puts '[DRY RUN] Operation would execute here (not running in dry-run mode)'
          return
        end

        yield
      end

      # Prompt for operation confirmation
      #
      # Displays confirmation prompt and waits for user input.
      # Can be bypassed with auto_yes flag.
      #
      # @param message [String] Confirmation message
      # @param auto_yes [Boolean] Automatically confirm (default: false)
      # @return [Boolean] True if confirmed, false otherwise
      #
      # @example
      #   return unless confirm_operation('Delete customer?', auto_yes: options[:yes])
      #
      def confirm_operation(message, auto_yes: false)
        return true if auto_yes

        print "#{message} (y/n): "
        response = begin
          $stdin.gets&.chomp&.downcase
        rescue StandardError
          nil
        end

        if response.nil?
          puts "\nNo input received (stdin closed?)"
          return false
        end

        response == 'y'
      end

      # Show progress for operations
      #
      # Displays progress with percentage for operations with many items.
      # Only shows progress if total > 5 items.
      #
      # @param current [Integer] Current item number
      # @param total [Integer] Total number of items
      # @param message [String] Optional message to display
      # @return [void]
      #
      # @example
      #   items.each_with_index do |item, i|
      #     show_progress(i + 1, items.size, "Processing #{item.name}")
      #     # ... process item
      #   end
      #
      def show_progress(current, total, message = nil)
        return if total <= 5 # Don't show progress for small operations

        percentage = ((current.to_f / total) * 100).round
        progress_bar = '=' * (percentage / 5) # 20 chars max
        status = "Progress: #{current}/#{total} (#{percentage}%) [#{progress_bar.ljust(20)}]"
        status += " #{message}" if message

        print "\r#{status}"
        $stdout.flush

        puts if current == total # New line when complete
      end

      # Display formatted table header
      #
      # @param headers [Array<String>] Column headers
      # @param widths [Array<Integer>] Column widths
      # @return [void]
      #
      # @example
      #   display_table_header(['ID', 'Name', 'Status'], [20, 30, 10])
      #
      def display_table_header(headers, widths)
        format_string = widths.map { |w| "%-#{w}s" }.join(' ')
        puts format(format_string, *headers)
        puts '-' * widths.sum + '-' * (widths.size - 1)
      end

      # Display success message
      #
      # Shows checkmark and success message with optional details.
      #
      # @param message [String] Success message
      # @param details [Hash] Optional details to display
      # @return [void]
      #
      # @example
      #   display_success('Customer created', { id: 'cus_123', email: 'user@example.com' })
      #
      def display_success(message, details = {})
        puts "\n✓ #{message}"

        details.each do |key, value|
          formatted_key = key.to_s.split('_').map(&:capitalize).join(' ')
          puts "  #{formatted_key}: #{value}"
        end
      end

      # Display error message
      #
      # Shows error message with optional remedial actions.
      #
      # @param message [String] Error message
      # @param actions [Array<String>] Suggested remedial actions
      # @return [void]
      #
      # @example
      #   display_error('Failed to create customer', [
      #     'Verify email address is valid',
      #     'Check Stripe API key is configured',
      #     'Review Stripe dashboard for details'
      #   ])
      #
      def display_error(message, actions = [])
        puts "\n✗ Error: #{message}"

        return if actions.empty?

        puts "\nSuggested actions:"
        actions.each do |action|
          puts "  - #{action}"
        end
      end

      # Validate required options
      #
      # Checks that all required options are present.
      # Displays error and returns false if any are missing.
      #
      # @param options [Hash] Options hash to validate
      # @param required [Array<Symbol>] Required option keys
      # @return [Boolean] True if all required options present
      #
      # @example
      #   return unless validate_required_options(options, [:subscription_id, :reason])
      #
      def validate_required_options(options, required)
        missing = required.select { |key| options[key].nil? || options[key].to_s.strip.empty? }

        return true if missing.empty?

        display_error(
          "Missing required options: #{missing.join(', ')}",
          ["Use --help to see required options"]
        )
        false
      end
    end
  end
end
