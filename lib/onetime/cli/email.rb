# lib/onetime/cli/email.rb
#
# frozen_string_literal: true

# Shared module for email CLI commands.
# Houses the canonical template list and any shared helpers.

module Onetime
  module CLI
    module Email
      AVAILABLE_TEMPLATES = [
        :secret_link,
        :welcome,
        :password_request,
        :incoming_secret,
        :feedback_email,
        :secret_revealed,
        :expiration_warning,
        :organization_invitation,
        :email_change_confirmation,
        :email_change_requested,
        :email_changed,
      ].freeze

      SAMPLES_PATH = File.expand_path('../mail/samples', __dir__)
    end
  end
end
