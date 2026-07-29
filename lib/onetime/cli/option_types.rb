# lib/onetime/cli/option_types.rb
#
# frozen_string_literal: true

# Numeric coercion for Dry::CLI options, which Dry::CLI itself does not do.
#
# THE DEFECT
#
# `Dry::CLI::Option#parser_options` (dry-cli-1.4.1/lib/dry/cli/option.rb:94-112)
# hands OptionParser a coercion class in exactly one case:
#
#     parser_options << Array if array?
#
# No other type is ever passed through, and the gem never validates the `type:`
# symbol it was given -- `integer` and `float` appear nowhere in dry-cli 1.4.1.
# So `type: :integer` is not an unimplemented feature, it is a phantom: silently
# accepted, silently ignored.
#
# The value that reaches `call` is therefore bimodal. An omitted flag falls
# through to `Command.default_params` and keeps whatever Ruby literal was
# declared; a supplied flag arrives as the raw String from OptionParser:
#
#     ots domains probe example.com                 #=> timeout 10    Integer
#     ots domains probe example.com --timeout 30    #=> timeout "30"  String
#     ots domains probe example.com --timeout abc   #=> timeout "abc" String
#
# Note the third line. There was no validation anywhere, so garbage propagated
# into Operations and IO calls untouched.
#
# WHY THIS IS CENTRAL RATHER THAN PER-CALL-SITE
#
# Thirty-five `type: :integer` declarations and one `type: :float` are spread
# across lib/onetime/cli and apps/**/cli. Every one of them already believes the
# declaration works; eleven of them were confirmed broken (String into
# Kernel#sleep, Array#take, Array#first, `[n, total].min`, `count >= limit`).
# Fixing the declaration is one change; fixing the call sites is thirty-six
# changes plus every future one.
#
# WHY IT HOOKS DISPATCH RATHER THAN THE COMMAND CLASSES
#
# The obvious implementation prepends a `call` wrapper to every command class.
# It works, but it puts a foreign method at the head of each command's ancestor
# chain, and `Klass.instance_method(:call)` then resolves to the wrapper instead
# of the command's own method. Several tryouts introspect exactly that -- for
# the declared keyword names (`.parameters`) and for the command's source text
# (`.source_location` fed to File.read) -- so the wrapper silently answered for
# a file the caller never asked about.
#
# Dry::CLI funnels every invocation through one private method. Both entry
# points -- `Dry::CLI#perform_command` (single-command CLI) and
# `Dry::CLI#perform_registry` (our case, `Dry::CLI.new(Onetime::CLI)`) -- open
# with `command, args = parse(...)`, and `parse` returns the built command
# instance alongside the parsed args. Prepending there gives one interception
# point, covers every command whether or not it descends from a project base
# class, and leaves each command's ancestor chain exactly as written.
#
# Coercion happens BEFORE `result.before_callbacks.run(command, **args)`, not
# between the callbacks and `call`. Callbacks receive the same `**args` splat
# the command does, so a callback reading a numeric option has the identical
# defect; there is one args shape for the whole dispatch and no window in which
# a half-coerced hash exists.
#
# NEWLY COVERED: `Onetime::CLI::SessionCommand` (lib/onetime/cli/session_command.rb)
# subclasses `Dry::CLI::Command` directly rather than either project base class.
# The per-class implementation skipped it; a dispatch-level hook cannot. It
# declares no numeric options today, but the hole is closed rather than
# documented.
#
# THE COUPLING, STATED PLAINLY
#
# `parse` is `@api private` in dry-cli. A gem upgrade that renames it or changes
# its return shape disables coercion silently. spec/cli/option_types_spec.rb
# pins the method's owner, arity and return contract so that upgrade fails a
# test instead of shipping.

require 'dry/cli'
require 'json'

module Onetime
  module CLI
    module OptionTypes
      # Base 10 is explicit and load-bearing. `Integer("010")` is 8 and
      # `Integer("0x1e")` is 30, because Kernel#Integer honours literal prefixes
      # when no base is given -- so a zero-padded `--timeout 010` would silently
      # mean 8 seconds. Operators type decimal.
      COERCIONS = {
        integer: ->(raw) { Integer(raw, 10, exception: false) },
        float: ->(raw) { Float(raw, exception: false) },
      }.freeze

      DESCRIPTIONS = {
        integer: 'an integer',
        float: 'a number',
      }.freeze

      # Prepended to Dry::CLI itself (below), NOT to the command classes.
      module Dispatch
        private

        # `super` returns `[built_command, parsed_args]`, or raises SystemExit
        # via Dry::CLI#help / #error -- in which case nothing here runs.
        def parse(command, arguments, names)
          built, args = super
          [built, OptionTypes.coerce(OptionTypes.params_for(built), args)]
        end
      end

      # Declared params (arguments + options) of a built command. Dry::CLI
      # registers classes, and `parse` hands back an instance, but a registry
      # may also be given an already-built command -- hence the Class check.
      def self.params_for(command)
        klass = command.is_a?(Class) ? command : command.class
        klass.respond_to?(:params) ? klass.params : []
      end

      # Coerce every declared numeric param that is present in `args`.
      #
      # Only String values are rewritten. An omitted flag already holds the
      # declared Integer/Float default, and nil is left alone so that
      # `default: nil` ("unset") stays distinguishable from zero -- several
      # commands, e.g. domains verify --limit, branch on exactly that.
      def self.coerce(params, args)
        params.each_with_object(args.dup) do |param, coerced|
          cast = COERCIONS[param.type]
          next unless cast

          key = param.name.to_sym
          next unless coerced.key?(key)

          raw = coerced[key]
          next unless raw.is_a?(String)

          coerced[key] = cast.call(raw) || invalid!(param, raw, json: args[:json])
        end
      end

      # Fail loudly rather than pass garbage to an Operation. Mirrors the
      # `error_exit` shape of the per-area CLI shared modules. Only three of the
      # twenty-nine affected files declare `--json`; `args[:json]` is nil for the
      # rest, which correctly selects the plain-text form.
      def self.invalid!(param, raw, json:)
        flag    = Dry::CLI::Inflector.dasherize(param.name)
        message = "--#{flag} must be #{DESCRIPTIONS.fetch(param.type)} (got #{raw.inspect})"

        puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
        exit 1
      end
    end
  end
end

# Install the hook at load time: the module and its single installation site
# belong together, and Ruby makes a repeated prepend a no-op.
Dry::CLI.prepend(Onetime::CLI::OptionTypes::Dispatch)
