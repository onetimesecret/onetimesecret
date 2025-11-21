# frozen_string_literal: true

module Onetime
  module CLI
    # Safety Helpers for Billing CLI Commands
    #
    # Provides confirmation prompts, dry-run mode, and safety checks
    # for destructive operations.
    #
    module BillingSafetyHelpers
      # Confirmation prompt for destructive operations
      #
      # @param message [String] Confirmation message
      # @param auto_yes [Boolean] Skip confirmation if true
      # @return [Boolean] True if confirmed
      def confirm_operation(message, auto_yes: false)
        return true if auto_yes

        puts "\n⚠️  #{message}"
        print "\nProceed? (y/n): "
        $stdin.gets.chomp.downcase == 'y'
      end

      # Display operation summary before execution
      #
      # @param title [String] Operation title
      # @param details [Hash] Operation details
      # @param dry_run [Boolean] Whether this is a dry run
      def display_operation_summary(title, details, dry_run: false)
        prefix = dry_run ? '[DRY RUN] ' : ''
        puts "\n#{prefix}#{title}:"

        details.each do |key, value|
          puts "  #{key}: #{value}"
        end
      end

      # Execute operation with dry-run support
      #
      # @param dry_run [Boolean] Whether to execute or just preview
      # @yield Block to execute if not dry run
      # @return [Object] Result of block execution or nil
      def execute_with_dry_run(dry_run: false)
        if dry_run
          puts "\n[DRY RUN] Operation not executed"
          nil
        else
          yield
        end
      end

      # Display progress indicator for list operations
      #
      # @param current [Integer] Current item number
      # @param total [Integer] Total items
      # @param item_name [String] Name of current item
      def show_progress(current, total, item_name = nil)
        return unless total > 5 # Only show for larger operations

        progress = (current.to_f / total * 100).round
        item_info = item_name ? " (#{item_name})" : ''
        print "\rProgress: #{current}/#{total} (#{progress}%)#{item_info}"
        puts if current == total # New line when complete
      end

      # Validate test mode for destructive test operations
      #
      # @return [Boolean] True if in test mode
      def validate_test_mode!
        return true if Stripe.api_key&.start_with?('sk_test_')

        puts 'Error: This command can only be used with test API keys (sk_test_*)'
        puts 'Current key starts with: ' + (Stripe.api_key || 'none')[0..10]
        false
      end

      # Display table header
      #
      # @param headers [Array<String>] Column headers
      # @param widths [Array<Integer>] Column widths
      def display_table_header(headers, widths)
        puts
        header_row = headers.each_with_index.map { |h, i| h.ljust(widths[i]) }.join(' ')
        puts header_row
        puts '-' * header_row.length
      end

      # Display success message with details
      #
      # @param message [String] Success message
      # @param details [Hash] Additional details
      def display_success(message, details = {})
        puts "\n✓ #{message}"

        details.each do |key, value|
          puts "  #{key}: #{value}"
        end
      end

      # Display error with actionable guidance
      #
      # @param error [Exception, String] Error to display
      # @param suggestions [Array<String>] Suggested actions
      def display_error(error, suggestions = [])
        message = error.is_a?(Exception) ? error.message : error
        puts "\n✗ Error: #{message}"

        return if suggestions.empty?

        puts "\nSuggested actions:"
        suggestions.each { |suggestion| puts "  - #{suggestion}" }
      end
    end
  end
end
