# lib/onetime/rsfc/parser.rb

require 'prism'
require 'json'

module Onetime
  module RSFC
    # Parser for Ruby Single File Components (.rue files)
    #
    # Parses .rue files into their constituent sections:
    # - <data> - JSON with server variable interpolation for client hydration
    # - <template> - Handlebars-style template with variable interpolation
    # - <logic> - Optional Ruby code for server-side processing
    #
    # Uses Prism for all parsing to avoid external dependencies on unmaintained
    # handlebars libraries while providing a clean handlebars subset.
    class Parser
      class ParseError < StandardError; end
      class SectionMissingError < ParseError; end
      class SectionDuplicateError < ParseError; end
      class InvalidSyntaxError < ParseError; end

      REQUIRED_SECTIONS = %w[data template].freeze
      OPTIONAL_SECTIONS = ['logic'].freeze
      ALL_SECTIONS      = (REQUIRED_SECTIONS + OPTIONAL_SECTIONS).freeze

      attr_reader :file_path, :content, :sections, :data_attributes

      def initialize(file_path)
        @file_path       = file_path
        @content         = File.read(file_path)
        @sections        = {}
        @data_attributes = {}
        @partials        = []
      end

      def parse!
        extract_sections!
        validate_required_sections!
        parse_data_attributes!
        extract_partials!
        validate_data_json!
        self
      end

      # Extract sections from the .rue file content
      def extract_sections!
        section_regex = %r{<(#{ALL_SECTIONS.join('|')})\s*([^>]*)>(.*?)</\1>}m

        @content.scan(section_regex) do |section_name, attributes, section_content|
          raise SectionDuplicateError, "Duplicate <#{section_name}> section in #{@file_path}" if @sections.key?(section_name)

          @sections[section_name] = section_content.strip

          # Store attributes for data section
          if section_name == 'data'
            @data_attributes = parse_attributes(attributes)
          end
        end
      end

      # Validate that required sections are present
      def validate_required_sections!
        missing_sections = REQUIRED_SECTIONS - @sections.keys
        return if missing_sections.empty?

        raise SectionMissingError, "Missing required sections in #{@file_path}: #{missing_sections.join(', ')}"
      end

      # Parse attributes from section opening tags
      def parse_attributes(attr_string)
        attributes = {}
        # Simple attribute parsing: key="value" or key='value'
        attr_string.scan(/(\w+)=["']([^"']+)["']/) do |key, value|
          attributes[key] = value
        end
        attributes
      end

      # Parse data section attributes (window, schema)
      def parse_data_attributes!
        @data_attributes['window'] ||= 'data' # Default window attribute
      end

      # Extract partial references from template section
      def extract_partials!
        return unless @sections['template']

        # Find {{> partial_name}} patterns
        @sections['template'].scan(/\{\{\s*>\s*(\w+)\s*\}\}/) do |match|
          @partials << match[0]
        end

        @partials.uniq!
      end

      # Validate that data section contains valid JSON structure
      def validate_data_json!
        return unless @sections['data']

        # Basic validation - check that it looks like JSON
        data_content = @sections['data'].strip

        # Should start with { and end with }
        unless data_content.start_with?('{') && data_content.end_with?('}')
          raise InvalidSyntaxError, "Data section must contain JSON object in #{@file_path}"
        end

        # NOTE: We don't parse JSON here because it contains {{variable}} interpolations
        # that need to be processed with context first
      end

      # Get list of partial dependencies
      def partials
        @partials.dup
      end

      # Get specific section content
      def section(name)
        @sections[name]
      end

      # Get data section window attribute (for window.data vs window.customName)
      def window_attribute
        @data_attributes['window']
      end

      # Get data section schema attribute (for future TypeScript integration)
      def schema_path
        @data_attributes['schema']
      end

      # Check if section exists
      def has_section?(name)
        @sections.key?(name)
      end

      # Get template with variables that need interpolation
      def template_variables
        return [] unless @sections['template']

        variables = []
        # Extract {{variable}} patterns (but not {{> partials}} or {{#if}} blocks)
        @sections['template'].scan(%r{\{\{\s*([^>#/\s][^}]*?)\s*\}\}}) do |match|
          var_name = match[0].strip
          # Skip handlebars helpers and block statements
          next if var_name.match?(/^(if|unless|each|with)\s/)

          variables << var_name
        end

        variables.uniq
      end

      # Get data section variables that need interpolation
      def data_variables
        return [] unless @sections['data']

        variables = []
        @sections['data'].scan(/\{\{\s*([^}]+)\s*\}\}/) do |match|
          variables << match[0].strip
        end

        variables.uniq
      end

      # Get all variables referenced in the file
      def all_variables
        (template_variables + data_variables).uniq
      end

      class << self
        # Parse a .rue file and return parser instance
        def parse_file(file_path)
          new(file_path).parse!
        end

        # Check if a file is a .rue file
        def rue_file?(file_path)
          File.extname(file_path) == '.rue'
        end
      end
    end
  end
end
