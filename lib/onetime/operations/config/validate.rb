# lib/onetime/operations/config/validate.rb
#
# frozen_string_literal: true

require 'yaml'
require 'erb'
require 'json'
require 'json_schemer'

module Onetime
  module Operations
    module Config
      # Validate the application configuration YAML against the JSON Schema
      # generated from `src/schemas/contracts/config/config.ts` (Zod source of
      # truth).
      #
      # The generated schema lives at
      # `generated/schemas/config/static.schema.json` and is produced by
      # `pnpm run schemas:json:generate`. It is gitignored and must be
      # regenerated whenever the Zod schema changes (CI does this before the
      # Ruby suite; see `.github/workflows/ci.yml`).
      #
      # Mirrors the structure of `Billing::Operations::Catalog::Validate` so
      # the two validators behave consistently.
      #
      # @example
      #   result = Onetime::Operations::Config::Validate.call
      #   result.errors.each { |e| puts "ERROR: #{e}" }
      #
      class Validate
        Result = Data.define(:success, :valid, :config_path, :schema_path, :errors) do
          def initialize(success:, valid: false, config_path: nil, schema_path: nil, errors: [])
            super
          end
        end

        # @param config_path [String, nil] Override config file path
        # @param schema_path [String, nil] Override schema file path
        # @param progress [Proc, nil] Called with status messages
        # @return [Result]
        def self.call(config_path: nil, schema_path: nil, progress: nil)
          new(config_path: config_path, schema_path: schema_path, progress: progress).call
        end

        def initialize(config_path:, schema_path:, progress:)
          @config_path = config_path || default_config_path
          @schema_path = schema_path || default_schema_path
          @progress    = progress
        end

        def call
          unless File.exist?(@config_path)
            return Result.new(success: false, config_path: @config_path, schema_path: @schema_path,
                              errors: ["Config file not found: #{@config_path}"])
          end

          unless File.exist?(@schema_path)
            return Result.new(success: false, config_path: @config_path, schema_path: @schema_path,
                              errors: ["Schema file not found: #{@schema_path} " \
                                       '(run `pnpm run schemas:json:generate`)'])
          end

          report("Validating #{@config_path}")
          report("Schema:    #{@schema_path}")

          config = load_config(@config_path)
          return Result.new(success: false, config_path: @config_path, schema_path: @schema_path,
                            errors: ['Failed to load config (YAML or ERB syntax error)']) unless config

          schema = load_schema(@schema_path)
          return Result.new(success: false, config_path: @config_path, schema_path: @schema_path,
                            errors: ['Failed to load schema (JSON syntax error)']) unless schema

          errors = []
          validate_with_schema(config, schema, errors)

          Result.new(
            success: true,
            valid: errors.empty?,
            config_path: @config_path,
            schema_path: @schema_path,
            errors: errors,
          )
        rescue StandardError => ex
          Result.new(success: false, config_path: @config_path, schema_path: @schema_path,
                     errors: ["#{ex.class}: #{ex.message}"])
        end

        private

        def report(message)
          @progress&.call(message)
        end

        def default_config_path
          File.join(Onetime::HOME, 'etc', 'defaults', 'config.defaults.yaml')
        end

        def default_schema_path
          File.join(Onetime::HOME, 'generated', 'schemas', 'config', 'static.schema.json')
        end

        def load_config(path)
          erb_template = ERB.new(File.read(path))
          yaml_content = erb_template.result
          parsed = YAML.safe_load(yaml_content, permitted_classes: [Symbol], symbolize_names: false, aliases: true)
          stringify_symbols(parsed)
        rescue Psych::SyntaxError, Psych::DisallowedClass
          nil
        end

        # Recursively coerce Ruby Symbol values to Strings so the loaded YAML
        # is representable in JSON Schema's type system. The shipped
        # config.defaults.yaml uses Ruby symbol notation in a few places
        # (e.g. `default_validation_type: :regex`) because the consuming
        # libraries (Truemail, etc.) want symbols at runtime — but JSON
        # Schema has no symbol type, so we normalize for validation only.
        def stringify_symbols(value)
          case value
          when Symbol then value.to_s
          when Hash   then value.transform_values { |v| stringify_symbols(v) }
          when Array  then value.map { |v| stringify_symbols(v) }
          else value
          end
        end

        def load_schema(path)
          JSON.parse(File.read(path))
        rescue JSON::ParserError
          nil
        end

        def validate_with_schema(config, schema, errors)
          schemer           = JSONSchemer.schema(schema)
          validation_errors = schemer.validate(config).to_a

          validation_errors.each do |error|
            location = error['data_pointer'].to_s.empty? ? 'root' : error['data_pointer']
            message  = error['error'] || error['type']
            errors << "Schema validation: #{location}: #{message}"
          end
        end
      end
    end
  end
end
