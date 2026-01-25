# apps/web/auth/config/email/verify_account.rb
#
# frozen_string_literal: true

module Auth::Config::Email
  module VerifyAccount
    def self.configure(auth)
      # Verify Account Email (sent during account creation)
      # Full mode: use Rodauth's verification URL (/verify-account?key=...)
      auth.create_verify_account_email do
        template = Onetime::Mail::Templates::Welcome.new(
          {
            email_address: email_to,
            verification_path: verify_account_email_link,
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
