# lib/rsfc/rhales.rb

require 'prism'
require 'erb'

module RSFC
    # Rhales - Ruby Handlebars-style template engine
    #
    # A lightweight handlebars subset implementation using Prism for parsing.
    # Supports variable interpolation, conditionals, iteration, and partials
    # without depending on external handlebars libraries.
    #
    # Supported syntax:
    # - {{variable}} - Variable interpolation with HTML escaping
    # - {{{variable}}} - Raw variable interpolation (no escaping)
    # - {{#if condition}} ... {{/if}} - Conditionals
    # - {{#unless condition}} ... {{/unless}} - Negated conditionals
    # - {{#each items}} ... {{/each}} - Iteration
    # - {{> partial_name}} - Partial inclusion
    # rubocop:disable Style/RegexpLiteral
    class Rhales
      class RenderError < StandardError; end
      class PartialNotFoundError < RenderError; end
      class UndefinedVariableError < RenderError; end

      attr_reader :template_content, :context, :partial_resolver

      def initialize(template_content, context, partial_resolver: nil)
        @template_content = template_content
        @context          = context
        @partial_resolver = partial_resolver
      end

      # Render template with context
      def render
        process_template(@template_content)
      rescue StandardError => ex
        raise RenderError, "Template rendering failed: #{ex.message}"
      end

      private

      # Process template and handle all substitutions
      def process_template(content)
        # Process partials first (they might contain other template syntax)
        content = process_partials(content)

        # Process block statements (if, unless, each)
        content = process_blocks(content)

        # Process variable interpolations
        process_variables(content)
      end

      # Process {{> partial_name}} inclusions
      def process_partials(content)
        content.gsub(/\{\{\s*>\s*(\w+)\s*\}\}/) do |match|
          partial_name = ::Regexp.last_match(1)

          if @partial_resolver
            partial_content = @partial_resolver.call(partial_name)
            raise PartialNotFoundError, "Partial '#{partial_name}' not found" unless partial_content

            # Recursively process the partial content
            process_template(partial_content)
          else
            # If no partial resolver, leave as-is (for testing)
            match
          end
        end
      end

      # Process block statements: {{#if}}, {{#unless}}, {{#each}}
      def process_blocks(content)
        # Process nested blocks from inside out
        loop do
          original_content = content

          # Process if blocks
          content = process_if_blocks(content)

          # Process unless blocks
          content = process_unless_blocks(content)

          # Process each blocks
          content = process_each_blocks(content)

          # Break if no more changes
          break if content == original_content
        end

        content
      end

      # Process {{#if condition}} ... {{/if}} blocks with optional {{else}}
      def process_if_blocks(content)
        content.gsub(/\{\{\s*#if\s+([^}]+)\s*\}\}(.*?)\{\{\s*\/if\s*\}\}/m) do |match|
          condition     = ::Regexp.last_match(1).strip
          block_content = ::Regexp.last_match(2)

          # Check for {{else}} clause
          if block_content.include?('{{else}}')
            if_part, else_part = block_content.split(/\{\{\s*else\s*\}\}/, 2)
            if evaluate_condition(condition)
              process_template(if_part)
            else
              process_template(else_part)
            end
          else
            # No else clause
            if evaluate_condition(condition)
              process_template(block_content)
            else
              ''
            end
          end
        end
      end

      # Process {{#unless condition}} ... {{/unless}} blocks
      def process_unless_blocks(content)
        content.gsub(/\{\{\s*#unless\s+([^}]+)\s*\}\}(.*?)\{\{\s*\/unless\s*\}\}/m) do |match|
          condition     = ::Regexp.last_match(1).strip
          block_content = ::Regexp.last_match(2)

          if evaluate_condition(condition)
            ''
          else
            process_template(block_content)
          end
        end
      end

      # Process {{#each items}} ... {{/each}} blocks
      def process_each_blocks(content)
        content.gsub(/\{\{\s*#each\s+([^}]+)\s*\}\}(.*?)\{\{\s*\/each\s*\}\}/m) do |match|
          items_var     = ::Regexp.last_match(1).strip
          block_content = ::Regexp.last_match(2)

          items = get_variable_value(items_var)

          if items.respond_to?(:each)
            items.map.with_index do |item, index|
              # Create context for each iteration
              item_context = create_each_context(item, index, items_var)
              engine       = self.class.new(block_content, item_context, partial_resolver: @partial_resolver)
              engine.render
            end.join
          else
            ''
          end
        end
      end

      # Process variable interpolations: {{variable}} and {{{variable}}}
      def process_variables(content)
        # Process raw variables first {{{variable}}}
        content = content.gsub(/\{\{\{\s*([^}]+)\s*\}\}\}/) do |match|
          variable_name = ::Regexp.last_match(1).strip
          value         = get_variable_value(variable_name)
          value.to_s
        end

        # Process escaped variables {{variable}}
        content.gsub(/\{\{\s*([^}]+)\s*\}\}/) do |match|
          variable_name = ::Regexp.last_match(1).strip
          # Skip if it's a block statement or partial
          next match if variable_name.match?(/^(#|\/|>)/)

          value = get_variable_value(variable_name)
          escape_html(value.to_s)
        end
      end

      # Get variable value from context
      def get_variable_value(variable_name)
        # Handle special variables
        case variable_name
        when 'this', '.'
          return @context.respond_to?(:current_item) ? @context.current_item : nil
        when '@index'
          return @context.respond_to?(:current_index) ? @context.current_index : nil
        end

        # Get from context
        if @context.respond_to?(:get)
          @context.get(variable_name)
        elsif @context.respond_to?(:[])
          @context[variable_name] || @context[variable_name.to_sym]
        else
          nil
        end
      end

      # Evaluate condition for if/unless blocks
      def evaluate_condition(condition)
        value = get_variable_value(condition)

        # Handle truthy/falsy evaluation
        case value
        when nil, false
          false
        when ''
          false
        when Array
          !value.empty?
        when Hash
          !value.empty?
        when 0
          false
        else
          true
        end
      end

      # Create context for each iteration
      def create_each_context(item, index, items_var)
        EachContext.new(@context, item, index, items_var)
      end

      # HTML escape for XSS protection
      def escape_html(string)
        ERB::Util.html_escape(string)
      end

      # Context wrapper for {{#each}} iterations
      class EachContext
        attr_reader :parent_context, :current_item, :current_index, :items_var

        def initialize(parent_context, current_item, current_index, items_var)
          @parent_context = parent_context
          @current_item   = current_item
          @current_index  = current_index
          @items_var      = items_var
        end

        def get(variable_name)
          # Handle special each variables
          case variable_name
          when 'this', '.'
            return @current_item
          when '@index'
            return @current_index
          when '@first'
            return @current_index == 0
          when '@last'
            # We'd need to know the total length for this
            return false
          end

          # Check if it's a property of the current item
          if @current_item.respond_to?(:[])
            item_value = @current_item[variable_name] || @current_item[variable_name.to_sym]
            return item_value unless item_value.nil?
          end

          if @current_item.respond_to?(variable_name)
            return @current_item.public_send(variable_name)
          end

          # Fall back to parent context
          @parent_context.get(variable_name) if @parent_context.respond_to?(:get)
        end

        def respond_to?(method_name)
          super || @parent_context.respond_to?(method_name)
        end

        def method_missing(method_name, *)
          if @parent_context.respond_to?(method_name)
            @parent_context.public_send(method_name, *)
          else
            super
          end
        end
      end

      class << self
        # Render template with context and optional partial resolver
        def render(template_content, context, partial_resolver: nil)
          new(template_content, context, partial_resolver: partial_resolver).render
        end

        # Create partial resolver that loads .rue files from a directory
        def file_partial_resolver(templates_dir)
          proc do |partial_name|
            partial_path = File.join(templates_dir, "#{partial_name}.rue")

            if File.exist?(partial_path)
              # Load and parse the partial .rue file
              parser = Parser.parse_file(partial_path)
              parser.section('template')
            else
              nil
            end
          end
        end
      end
    end
  # rubocop:enable Style/RegexpLiteral
end
