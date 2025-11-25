# apps/web/auth/config/email.rb
#
# frozen_string_literal: true

require 'onetime/mail'

module Auth::Config::Email
  def self.configure(auth)
    # Configure Rodauth email settings
    auth.email_from Onetime::Mail::Mailer.from_address
    auth.email_subject_prefix ENV['EMAIL_SUBJECT_PREFIX'] || '[OneTimeSecret] '

    # Configure email delivery using unified mailer
    auth.send_email do |email|
      Onetime.auth_logger.debug 'send_email hook called', {
        subject: email.subject.to_s,
        to: email.to.to_s,
        rack_env: ENV.fetch('RACK_ENV', nil),
      }

      # Deliver email using unified Onetime::Mail system
      Onetime::Mail.deliver_raw(
        to: email.to,
        from: email.from,
        subject: email.subject,
        body: email.body.to_s
      )
    end

    OT.info "[email] Email delivery configured"
  end
end
