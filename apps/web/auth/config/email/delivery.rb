# apps/web/auth/config/email/delivery.rb
#
# frozen_string_literal: true

require_relative '../../../../../lib/onetime/jobs/publisher'

module Auth::Config::Email
  module Delivery
    def self.configure(auth)
      # Configure email delivery using unified mailer
      auth.send_email do |email|
        Onetime.auth_logger.debug 'send_email hook called',
          {
            subject: email.subject.to_s,
            to: email.to.to_s,
            multipart: email.multipart?,
            rack_env: ENV.fetch('RACK_ENV', nil),
          }

        # Extract body content from multipart or simple email
        body_content = if email.multipart?
                         # For multipart, prefer text part for plain email delivery
                         # (Our mailer will send the plain text version)
                         email.text_part&.body&.decoded || email.body.to_s
                       else
                         email.body.to_s
                       end

        # Critical auth flow (verification, password reset): use sync fallback
        # Rodauth emails must be delivered - user is waiting for auth action
        Onetime::Jobs::Publisher.enqueue_email_raw(
          {
            to: email.to,
            from: email.from,
            subject: email.subject,
            body: body_content,
          },
          fallback: :sync,
        )
      end
    end
  end
end
