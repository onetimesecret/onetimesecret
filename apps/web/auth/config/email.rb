# apps/web/auth/config/email.rb
#
# frozen_string_literal: true

require 'onetime/mail'
require_relative '../../../../lib/onetime/jobs/publisher'

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

      # Critical auth flow (verification, password reset): use sync fallback
      # Rodauth emails must be delivered - user is waiting for auth action
      Onetime::Jobs::Publisher.enqueue_email_raw({
        to: email.to,
        from: email.from,
        subject: email.subject,
        body: email.body.to_s,
      }, fallback: :sync
                                                )
    end

    OT.info '[email] Email delivery configured'
  end
end
