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
# WHY IT PREPENDS TO EVERY SUBCLASS
#
# A prepended module only precedes the methods of the class it is prepended to.
# `DlqListCommand < DlqBase < Command` defines its own `call`, so prepending to
# `DlqBase` alone would leave `DlqListCommand#call` ahead of the coercion in the
# ancestor chain and silently bypass it. `Command.inherited` therefore prepends
# to each subclass unconditionally, and the module legitimately appears more
# than once in a chain like DlqListCommand's. That is harmless: the second pass
# sees a value that is no longer a String and skips it.
#
# NOT COVERED: `Onetime::CLI::SessionCommand` (lib/onetime/cli/session_command.rb)
# subclasses `Dry::CLI::Command` directly rather than either project base class,
# so it does not get this hook. It declares no numeric options today.

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

      # Prepended to every command class by Command.inherited /
      # DelayBootCommand.inherited (lib/onetime/cli.rb).
      module Coercion
        def call(**args)
          super(**OptionTypes.coerce(self.class.params, args))
        end
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
