# apps/web/auth/config/email/reset_password.rb
#
# frozen_string_literal: true

module Auth::Config::Email
  module ResetPassword
    def self.configure(auth)
      # Reset Password Email (sent when user requests password reset)
      # Full mode: use Rodauth's reset URL (/reset-password?key=...)
      auth.create_reset_password_email do
        template = Onetime::Mail::Templates::PasswordRequest.new(
          {
            email_address: email_to,
            reset_password_path: reset_password_email_link,
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
