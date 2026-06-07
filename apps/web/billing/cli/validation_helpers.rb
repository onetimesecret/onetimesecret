# apps/web/billing/cli/validation_helpers.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Shared validation helpers for billing commands
    # Used by prices_validate, plans_validate, products_validate, and
    # orgs_validate commands.
    module ValidationHelpers
      # Status indicators (consistent across all validation commands)
      STATUS_VALID      = '✓ Valid'
      STATUS_WARNING    = '⚠ Warning'
      STATUS_ERROR      = '✗ Invalid'
      STATUS_UNUSABLE   = '✗ Unusable'
      STATUS_INCOMPLETE = '⚠ Incomplete'
      STATUS_READY      = '✓ Ready'
      STATUS_NOT_READY  = '✗ Not Ready'

      # Column widths for consistent table formatting
      PRICE_ID_WIDTH     = 31        # Full Stripe price ID (29 chars + padding)
      PRODUCT_ID_WIDTH   = 22      # Full Stripe product ID (20 chars + padding)
      PRODUCT_NAME_WIDTH = 25
      PLAN_ID_WIDTH      = 20
      AMOUNT_WIDTH       = 12
      INTERVAL_WIDTH     = 9
      REGION_WIDTH       = 7
      PRICES_COUNT_WIDTH = 16
      STATUS_WIDTH       = 15

      # Determines status for a price based on errors and warnings
      #
      # @param price [Stripe::Price] The price object
      # @param errors [Array<Hash>] Array of structured error hashes
      # @param warnings [Array<Hash>] Array of structured warning hashes
      # @return [String] Status indicator string
      def status_for_price(price, errors, warnings)
        price_errors   = errors.select { |e| e.is_a?(Hash) && e[:price_id] == price.id }
        price_warnings = warnings.select { |w| w.is_a?(Hash) && w[:price_id] == price.id }

        return STATUS_UNUSABLE if price_errors.any? { |e| e[:type] == :archived_product }
        return STATUS_ERROR if price_errors.any?
        return STATUS_WARNING if price_warnings.any?

        STATUS_VALID
      end

      # Determines status for a plan/product based on errors and warnings
      #
      # @param product_id [String] The product ID
      # @param errors [Array<Hash>] Array of structured error hashes
      # @param warnings [Array<Hash>] Array of structured warning hashes
      # @return [String] Status indicator string
      def status_for_product(product_id, errors, warnings)
        product_errors   = errors.select { |e| e.is_a?(Hash) && e[:product_id] == product_id }
        product_warnings = warnings.select { |w| w.is_a?(Hash) && w[:product_id] == product_id }

        return STATUS_NOT_READY if product_errors.any?
        return STATUS_INCOMPLETE if product_warnings.any?

        STATUS_READY
      end

      # Generates Stripe dashboard URL for a resource
      #
      # @param type [Symbol] Resource type (:price, :product, :plan)
      # @param id [String] Stripe resource ID
      # @return [String] Full dashboard URL
      def stripe_dashboard_url(type, id)
        base = if Stripe.api_key.start_with?('sk_live_')
                 'https://dashboard.stripe.com'
               else
                 'https://dashboard.stripe.com/test'
               end

        case type
        when :price
          "#{base}/prices/#{id}"
        when :product
          "#{base}/products/#{id}"
        when :plan
          "#{base}/billing/subscriptions/products/#{id}"
        else
          base
        end
      end

      # Prints a separator line
      #
      # @param width [Integer] Line width (default: 80)
      # @param char [String] Character to use (default: '━')
      def print_separator(width = 80, char = '━')
        puts char * width
      end

      # Prints a section header
      #
      # @param title [String] Section title
      # @param width [Integer] Line width (default: 80)
      # @param char [String] Separator character (default: '━')
      def print_section_header(title, width = 80, char = '━')
        print_separator(width, char)
        puts title
        print_separator(width, char)
      end

      # Prints structured errors with details and resolution steps
      #
      # @param errors [Array<Hash>] Array of structured error hashes
      # @param width [Integer] Line width (default: 80)
      def print_errors_section(errors, width = 80)
        structured_errors = errors.grep(Hash)
        string_errors     = errors.grep(String)

        return if structured_errors.empty? && string_errors.empty?

        print_section_header("ERRORS (#{errors.size})", width)
        puts

        structured_errors.each do |error|
          identifier = error[:price_id] || error[:product_id]
          puts "  ✗ #{identifier}: #{error[:message]}"
          puts
          puts "    #{error[:details]}" if error[:details]
          puts
          next unless error[:resolution]

          puts '    Resolution:'
          error[:resolution].each { |step| puts "    - #{step}" }
          puts
        end

        string_errors.each { |error| puts "  ✗ #{error}" }
        puts if string_errors.any?
      end

      # Prints structured warnings with details
      #
      # @param warnings [Array<Hash>] Array of structured warning hashes
      # @param width [Integer] Line width (default: 80)
      def print_warnings_section(warnings, width = 80)
        structured_warnings = warnings.grep(Hash)
        string_warnings     = warnings.grep(String)

        return if structured_warnings.empty? && string_warnings.empty?

        print_section_header("WARNINGS (#{warnings.size})", width)
        puts

        structured_warnings.each do |warning|
          identifier = warning[:price_id] || warning[:product_id]
          puts "  ⚠ #{identifier}: #{warning[:message]}"
          puts
          puts "    #{warning[:details]}" if warning[:details]
          puts
          next unless warning[:resolution]

          puts '    Resolution:'
          warning[:resolution].each { |step| puts "    - #{step}" }
          puts
        end

        string_warnings.each { |warning| puts "  • #{warning}" }
        puts if string_warnings.any?
      end

      # Prints final validation status
      #
      # @param errors [Array] Array of errors
      # @param warnings [Array] Array of warnings
      # @param strict [Boolean] Whether to treat warnings as errors
      # @param width [Integer] Line width (default: 80)
      def print_final_status(errors, warnings, strict, width = 80)
        print_separator(width)

        if errors.any?
          puts '❌  VALIDATION FAILED'
          print_separator(width)
          puts
          puts "#{errors.size} item(s) have errors that must be fixed."
          puts 'Fix errors above or use --help for guidance.'
          puts
        elsif warnings.any? && strict
          puts '❌  VALIDATION FAILED'
          print_separator(width)
          puts
          puts "#{warnings.size} warning(s) treated as errors in strict mode."
          puts
        elsif warnings.any?
          puts '✅  VALIDATION PASSED'
          print_separator(width)
          puts
          puts "All items are valid (#{warnings.size} warning(s) found)."
          puts
          puts 'Run with --strict to treat warnings as errors.'
          puts
        else
          puts '✅  VALIDATION PASSED'
          print_separator(width)
          puts
          puts 'All items are valid and ready for use.'
          puts
        end
      end

      # Counts valid items based on errors and warnings
      #
      # @param items [Array] Array of items to count
      # @param errors [Array<Hash>] Array of errors
      # @param warnings [Array<Hash>] Array of warnings
      # @param id_field [Symbol] Field name for ID (:id for prices, :product_id for products)
      # @return [Integer] Count of valid items
      def count_valid_items(items, errors, warnings, id_field = :id)
        error_ids   = errors.grep(Hash).map { |e| e[:price_id] || e[:product_id] }.compact.uniq
        warning_ids = warnings.grep(Hash).map { |w| w[:price_id] || w[:product_id] }.compact.uniq

        items.count do |item|
          item_id = item.is_a?(Hash) ? item[id_field] : item.send(id_field)
          !error_ids.include?(item_id) && !warning_ids.include?(item_id)
        end
      end

      # Prints an in-place progress indicator to stdout.
      #
      # Emits a CR-prefixed line at most every `interval` iterations (and
      # always on the final iteration). Caller is responsible for calling
      # {#clear_progress_line} when the loop completes.
      #
      # @param current [Integer] Current iteration count (1-indexed)
      # @param total [Integer] Total iterations expected
      # @param interval [Integer] How often to emit progress (every Nth iteration)
      # @param label [String] What's being processed (e.g., 'organizations scanned')
      def print_progress(current, total, interval, label: 'items processed')
        return unless (current % interval).zero? || current == total

        print "\r  Progress: #{current}/#{total} #{label}"
        $stdout.flush
      end

      # Clears the current progress line from stdout.
      #
      # Overwrites the line with whitespace and resets the cursor to the
      # start of the line, allowing subsequent output to begin cleanly.
      #
      # @param width [Integer] Width of the line to clear (default: 80)
      def clear_progress_line(width = 80)
        print "\r" + (' ' * width) + "\r"
        $stdout.flush
      end

      # Prints a standalone "Resolution:" block listing next-step hints.
      #
      # Use this for commands that surface aggregate guidance (e.g., a list
      # of operator commands to run after a scan) separate from structured
      # per-item errors. Structured errors should embed their own
      # `:resolution` array and let {#print_errors_section} render them.
      #
      # @param steps [Array<String>] Resolution hint lines to print
      # @param width [Integer] Separator line width (default: 60)
      # @param char [String] Separator character (default: '-')
      # @param label [String] Heading label (default: 'Resolution:')
      def print_resolution_section(steps, width: 60, char: '-', label: 'Resolution:')
        return if steps.empty?

        print_separator(width, char)
        puts label
        steps.each { |step| puts "  - #{step}" }
        puts
      end
    end
  end
end
