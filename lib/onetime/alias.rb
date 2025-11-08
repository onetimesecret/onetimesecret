# lib/onetime/alias.rb
#
# frozen_string_literal: true

# typed: ignore

# This file exists solely to define the OT = Onetime constant.
# Defining this constant in onetime.rb file triggers Sorbet error
# 4022. To avoid this error and maintain type safety, we move the
# definition to this file which we can set to typed: ignore.
#
#    lib/onetime/cli.rb:7: Previously defined as a class or module here
#    7 |class OT::CLI < Drydock::Command
#
# Sorbet error 4022: Sorbet does not allow treating constant
# assignments as class or module definitions, even if the
# initializer computes a Module object at runtime.
#
# See:
#   - https://sorbet.org/docs/error-reference#4022
#   - https://github.com/Shopify/tapioca/pull/1756

OT = Onetime
