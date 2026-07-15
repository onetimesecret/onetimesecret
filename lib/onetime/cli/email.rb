# lib/onetime/cli/email.rb
#
# frozen_string_literal: true

# Shared module for email CLI commands.
#
# The canonical template list and sample-data path now live in the extracted
# central operation {Onetime::Operations::Email::PreviewTemplate} (ticket #44) —
# the SINGLE source shared by the colonel API, the ops, and this CLI. These
# aliases keep every existing `Onetime::CLI::Email::AVAILABLE_TEMPLATES` /
# `SAMPLES_PATH` reference working with a byte-identical value.

require 'onetime/operations/email/preview_template'

module Onetime
  module CLI
    module Email
      AVAILABLE_TEMPLATES = Onetime::Operations::Email::AVAILABLE_TEMPLATES
      SAMPLES_PATH        = Onetime::Operations::Email::SAMPLES_PATH
    end
  end
end
