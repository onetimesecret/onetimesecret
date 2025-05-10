## User Question about handling nil or empty config

Question about a more broad scenario: The configuration that eventually gets to Onetime.conf starts out being passed in to Onetime::Config.after_load. If the value passed in to after_load is nil or an empty hash, that means the yaml config file is missing or an empty yaml file. There is a lot of logic in the codebase, built around the assumption that OT.conf (and it's cohort, OT.d9s_enabled etc) have values set.

The question is one about healthy programming practices in a growing, complex opensource codebase. What would be the conventional or idiomatic approach for an opensource ruby web application project for handling a nil or empty hash being passed in to after_load (that is not rails and does not use rails so does not need to follow rails conventions).

## Agent

That's an excellent question that touches upon crucial aspects of maintaining a robust and developer-friendly open-source project. When `Onetime::Config.after_load` receives `nil` or an empty hash (indicating a missing or empty YAML configuration file), the application needs a clear and predictable way to behave.

Here's a breakdown of conventional and idiomatic approaches for a Ruby web application like Onetime (non-Rails) to handle this scenario:

1.  **Fail Fast for Critical Configuration:**
    *   **Principle:** If certain configuration values are absolutely essential for the application's core functionality (e.g., database connection details without sensible defaults, primary domain name, secret key for session encryption), the application should refuse to start or operate in a degraded, potentially unsafe state.
    *   **Implementation:**
        *   `Onetime::Config.after_load` (or a dedicated validation step within it or called by it) should check for these critical keys after attempting to apply any defaults.
        *   If critical keys are still missing or invalid, it should raise a specific, informative error (e.g., `Onetime::ConfigError < StandardError`).
        *   The `Onetime.boot!` method, which calls `after_load`, would then catch this error. Its existing rescue block (`rescue OT::Problem => e` or a more specific one for config errors) would log the issue and re-raise the exception (unless in `:cli` mode, as per your current logic), effectively preventing the application from proceeding with an incomplete critical setup.
    *   **Benefit:** Prevents silent failures or undefined behavior later on. Makes it immediately obvious to the user/developer that a crucial setup step is missing.

2.  **Provide Sensible Defaults:**
    *   **Principle:** For many configuration options, you can define reasonable default values that allow the application to run out-of-the-box for development, testing, or basic use cases without requiring an explicit configuration file.
    *   **Implementation:**
        *   Your `Onetime::Config.apply_defaults` method is key here. It should be designed to take the loaded configuration (which might be an empty hash if the file was empty or missing) and merge it with a predefined hash of default values.
        *   The defaults should be comprehensive enough to cover non-critical settings.
    *   **Benefit:** Lowers the barrier to entry for new users and developers. Simplifies setup for common scenarios.

3.  **Clear Separation of Concerns in Config Loading:**
    *   `Onetime::Config.load`: Its primary responsibility should be to read the configuration file and parse it. If the file is missing or empty, it should gracefully return `nil` or an empty hash (e.g., `Hash.new`). It should not be responsible for defaults or validation.
    *   `Onetime::Config.after_load`: This method takes the raw loaded config (or `nil`/`{}`) and is responsible for:
        1.  Ensuring it's working with a hash (e.g., `loaded_config ||= {}`).
        2.  Applying defaults.
        3.  Performing any necessary transformations or normalizations.
        4.  **Validating** the resulting configuration (checking for critical missing pieces as per point 1).
        5.  Freezing the configuration.
    *   **Benefit:** Makes the configuration process more modular, testable, and easier to understand.

4.  **Configuration Schema and Validation (Optional but Recommended for Complexity):**
    *   **Principle:** As complexity grows, explicitly defining a schema for your configuration can be very helpful.
    *   **Implementation:** You could use a lightweight schema definition and validation library (or custom logic) to check for required keys, data types, and allowed values. This validation would occur in `after_load` after defaults are applied.
    *   **Benefit:** Catches configuration errors early and provides more structured error messages. Acts as documentation for the configuration structure.

5.  **Informative Error Messages and Guidance:**
    *   **Principle:** When the application does fail due to missing configuration, the error messages should be as helpful as possible.
    *   **Implementation:**
        *   The `Onetime::ConfigError` (or similar) should clearly state which configuration is missing or invalid.
        *   It could suggest creating a configuration file, pointing to `config.example.yaml` or documentation.
    *   **Benefit:** Helps users resolve the issue quickly.

**Applying to `Onetime::Config.after_load` and `Onetime.boot!`:**

*   **`Onetime::Config.load` modification:**
    Ensure `Onetime::Config.load` returns an empty hash if the YAML file is empty or if `YAML.load` returns `false` or `nil`. If the file doesn't exist, `File.read` would raise an `Errno::ENOENT`, which `Onetime::Config.load` should probably rescue and then return an empty hash, perhaps logging a debug message that the file wasn't found.

    ```ruby
    # In Onetime::Config
    def self.load(config_path = path, environment = OT.env)
      # ... (existing logic to find config_file)
      if File.exist?(config_file)
        begin
          raw_config = ERB.new(File.read(config_file)).result
          conf = YAML.safe_load(raw_config, aliases: true)
          conf.is_a?(Hash) ? conf : {} # Ensure it's a hash, even if YAML is just a value
        rescue Psych::SyntaxError => e
          OT.le "YAML syntax error in #{config_file}: #{e.message}"
          {} # Return empty hash on parse error
        end
      else
        OT.ld "Configuration file not found: #{config_file}. Using defaults."
        {} # Return empty hash if file doesn't exist
      end
    rescue Errno::ENOENT
      OT.ld "Configuration file not found during load: #{config_file}. Using defaults."
      {}
    rescue StandardError => e
      OT.le "Error loading configuration #{config_file}: #{e.message}"
      OT.ld e.backtrace.join("\n")
      {} # Fallback to empty hash
    end
    ```

*   **`Onetime::Config.after_load` enhancements:**
    1.  It receives `raw_conf` (which would be `{}` if the file was missing/empty/invalid).
    2.  It calls `apply_defaults(conf)`.
    3.  **Add a validation step:**
        ```ruby
        # In Onetime::Config, within after_load, after apply_defaults
        validate_essential_config(conf)
        # ... rest of after_load

        # private class method
        def self.validate_essential_config(conf)
          # Example: Check for a critical site setting that has no sensible default
          # and must be provided by the user.
          unless conf.dig(:site, :host).is_a?(String) && !conf.dig(:site, :host).empty?
            raise Onetime::ConfigError, "Critical configuration missing: 'site.host' must be defined in your config file (#{path}). This is typically the primary domain name for the service."
          end

          # Example: Check for redis configuration if it's absolutely essential
          # and defaults aren't sufficient for a basic run.
          unless conf.dig(:redis, :host) && conf.dig(:redis, :port)
            # This might be too strict if you have good defaults or can run without Redis for some modes.
            # Adjust based on actual application requirements.
            # raise Onetime::ConfigError, "Critical configuration missing: Redis host and port must be configured."
          end

          # Add other checks for truly indispensable settings.
        end
        ```
        You would define `Onetime::ConfigError < StandardError` (or `OT::Problem`) in your codebase.

*   **`Onetime.boot!`:**
    The existing `rescue OT::Problem => e` or `rescue StandardError => e` blocks in `boot!` would catch `Onetime::ConfigError` if it's a subclass, or you could add a specific `rescue Onetime::ConfigError => e`. The behavior of logging and re-raising (unless `:cli`) is appropriate.

**Summary for Onetime:**

The most idiomatic approach would be a combination:
1.  **Gracefully handle missing/empty config files in `Onetime::Config.load`** by returning an empty hash.
2.  **Rely heavily on `Onetime::Config.apply_defaults`** in `after_load` to provide a functional baseline.
3.  **Implement explicit checks in `Onetime::Config.after_load` (e.g., in `validate_essential_config`)** for a *small, well-defined set* of truly critical configuration parameters that lack safe defaults and are essential for the application to function at all.
4.  If these critical parameters are missing after defaults, **`after_load` raises an `Onetime::ConfigError`**.
5.  **`Onetime.boot!` catches this error**, logs it, and halts the application (unless in CLI mode), preventing it from running in an undefined or unsafe state.

This ensures that `OT.conf` and its related global state variables are populated with either user-defined values or sensible defaults, and the application only proceeds if all *critical* requirements are met. For everything else, the defaults allow for a smoother experience.

## Recommendations for Configuration Schema and Validation

Ways the validation of your configuration, which is a great step for a growing project. This helps catch errors early, provides clearer feedback to users/developers, and serves as a form of documentation for your configuration structure.

Given Onetime is a Ruby application and you're not bound by Rails conventions, here are a few recommendations for configuration schema and validation, ranging from lightweight to more comprehensive:

1.  **Custom Validation Logic (Your Current Direction)**
    *   **Description:** As we discussed, you can build this directly into your `Onetime::Config.after_load` method or a helper it calls. This involves manually checking for key presence, types, and valid values.
    *   **Pros:**
        *   No new dependencies.
        *   Full control over logic and error messages.
    *   **Cons:**
        *   Can become verbose and harder to maintain as the configuration schema grows.
        *   Error reporting might be less standardized unless you build a robust system for it.
        *   Type checking can be manual and error-prone.
    *   **Best for:** Smaller configuration files or when you want to avoid external dependencies at all costs.

2.  **`dry-schema` (from the Dry-rb ecosystem)**
    *   **Description:** `dry-schema` is a powerful data coercion and validation library. It provides a DSL (Domain Specific Language) to define schemas, including types, required/optional keys, and more complex rules.
    *   **Pros:**
        *   **Clear DSL:** Schemas are easy to read and write.
        *   **Type Safety:** Enforces data types (e.g., string, integer, boolean, nested hashes).
        *   **Detailed Error Messages:** Generates structured error messages that pinpoint what's wrong.
        *   **Coercion:** Can automatically coerce input values (e.g., string "true" to boolean `true`).
        *   **Well-maintained and part of a respected ecosystem.**
    *   **Cons:**
        *   Adds an external dependency (`dry-schema` and its own dependencies like `dry-core`, `dry-logic`).
        *   Slight learning curve if you're new to Dry-rb.
    *   **Integration into `Onetime::Config.after_load`:**
        You would define a schema and then validate the configuration (after defaults are applied) against it.

        ```ruby
        # /dev/null/onetime_config_schema.rb (Conceptual Example)
        # require 'dry-schema'
        #
        # OnetimeConfigSchema = Dry::Schema.Params do # Or Dry::Schema.JSON if not dealing with form params
        #   required(:site).hash do
        #     required(:host).filled(:string)
        #     required(:domain).filled(:string)
        #     optional(:secret_options).array(:string) # Example
        #     # ... other site settings
        #   end
        #
        #   required(:redis).hash do
        #     required(:host).filled(:string)
        #     required(:port).filled(:integer)
        #     # ... other redis settings
        #   end
        #
        #   optional(:diagnostics).hash do
        #     required(:enabled).bool
        #     optional(:dsn).maybe(:string) # 'maybe' allows nil or the specified type
        #   end
        #
        #   # ... other top-level sections
        # end

        # In Onetime::Config.after_load(raw_conf)
        # ...
        # conf = apply_defaults(raw_conf || {}) # Ensure conf is a hash
        #
        # validation_result = OnetimeConfigSchema.call(conf)
        #
        # if validation_result.failure?
        #   # validation_result.errors.to_h provides a detailed hash of errors
        #   # You can format this into a user-friendly message
        #   error_messages = validation_result.errors.to_h.map do |field, messages|
        #     "Config error for '#{field}': #{messages.join(', ')}"
        #   end.join("; ")
        #   raise Onetime::ConfigError, "Configuration validation failed: #{error_messages}"
        # end
        #
        # # If validation passes, conf is valid according to the schema.
        # # dry-schema can also return the coerced/typed data if you use its output.
        # # For example: validated_conf = validation_result.to_h
        # # Then you'd use validated_conf going forward.
        #
        # @conf = deep_freeze(conf) # Or deep_freeze(validated_conf)
        # ...
        ```
    *   **Best for:** Projects that anticipate growing configuration complexity and value robust validation and clear error reporting.

3.  **JSON Schema with a Ruby Validator (e.g., `json-schema` gem)**
    *   **Description:** Define your schema in a standard JSON Schema file (`.json`). Then use a Ruby gem to validate your configuration hash against this schema.
    *   **Pros:**
        *   **Standardized:** JSON Schema is a widely adopted standard.
        *   **Language Agnostic:** The schema definition itself isn't tied to Ruby.
        *   Good for interoperability if other tools or services need to understand your config structure.
    *   **Cons:**
        *   Schema definition is in JSON, which can be more verbose than a Ruby DSL.
        *   Adds an external dependency.
    *   **Integration:** Similar to `dry-schema`, you'd load your schema and validate the config hash in `after_load`.
    *   **Best for:** Situations where adherence to the JSON Schema standard is a priority, or if you need to share the schema definition across different programming languages.

4.  **Lightweight Contract Libraries (e.g., `contracts.ruby`)**
    *   **Description:** While primarily for method contracts, libraries like `contracts.ruby` can be adapted to validate data structures.
    *   **Pros:**
        *   Can enforce types and structure.
        *   Ruby-centric.
    *   **Cons:**
        *   May not be as specifically tailored for configuration validation as `dry-schema`.
        *   The primary focus is on runtime checking of method arguments/return values.
    *   **Best for:** If you're already using such a library for other purposes in your project and want to leverage it for configuration as well.

**Recommendations for Onetime:**

Considering Onetime's current state and the desire for robust, maintainable code:

*   **If you prefer minimal dependencies:** Continue refining your **custom validation logic**. Focus on creating helper methods that provide clear error messages and make the validation rules readable within `Onetime::Config`.
*   **For a more structured and scalable approach:** I would strongly recommend looking into **`dry-schema`**.
    *   It provides a good balance of power, a clean Ruby DSL for schema definition, and excellent error reporting.
    *   It will make your configuration rules explicit and easier to manage as the application evolves.
    *   The ability to get coerced, typed data back from the validation can also reduce boilerplate type checks elsewhere.

**Steps if you choose `dry-schema` (or similar):**

1.  **Add the gem:** `pnpm add -D @types/dry-schema` (if using something like `package.json` for Ruby gems via a bridge, or directly in your `Gemfile`: `gem 'dry-schema'`).
2.  **Define your schema:** Create a Ruby file (e.g., `lib/onetime/config_schema.rb`) to define your `OnetimeConfigSchema` using the `dry-schema` DSL. This schema should reflect the structure *after* defaults are applied.
3.  **Integrate into `Onetime::Config.after_load`:**
    *   Load/require your schema definition.
    *   After applying defaults to the `raw_conf`, pass the resulting `conf` hash to your schema for validation (`YourSchema.call(conf)`).
    *   Check `validation_result.success?` or `validation_result.failure?`.
    *   If it fails, extract the error messages (`validation_result.errors.to_h`) and raise an `Onetime::ConfigError` with a well-formatted summary.
    *   If it succeeds, you can use the (potentially coerced) output from the validation (`validation_result.to_h`) as your final configuration hash before freezing.

This approach will make your configuration handling more declarative and robust.
