# apps/web/auth/config/email/email_auth.rb
#
# frozen_string_literal: true

module Auth::Config::Email
  # Email Auth (Magic Link) email configuration
  #
  # Configures the email template for passwordless login links.
  # Uses the MagicLink template class for i18n support.
  #
  module EmailAuth
    def self.configure(auth)
      # Email Auth / Magic Link Email
      # Sent when user requests passwordless login
      auth.create_email_auth_email do
        template = Onetime::Mail::Templates::MagicLink.new(
          {
            email_address: email_to,
            magic_link_path: email_auth_email_link,
            baseuri: request.base_url,
            product_name: OT.conf.dig('site', 'product_name'),
            display_domain: request.host,
          },
          locale: determine_account_locale,
        )

        build_multipart_email(template)
      end
    end
  end
end
