# .purgatory/lib-onetime-mail.rb
#
# frozen_string_literal: true

require_relative 'mail/views'

require_relative 'mail/mailer/base_mailer'
require_relative 'mail/mailer/smtp_mailer'
require_relative 'mail/mailer/sendgrid_mailer'
require_relative 'mail/mailer/ses_mailer'

module Onetime
  module Mail
    @mailer = nil

    # Returns the configured mailer instance
    def self.mailer
      @mailer ||= begin
        provider = OT.conf['emailer']['provider'] || 'smtp'
        from     = OT.conf['emailer']['from']
        from_name = OT.conf['emailer']['from_name'] || OT.conf['emailer']['from_name'] # since v0.23

        case provider.to_s.downcase
        when 'sendgrid'
          Mailer::SendGridMailer.setup
          Mailer::SendGridMailer.new(from, from_name)
        when 'ses'
          Mailer::SESMailer.setup
          Mailer::SESMailer.new(from, from_name)
        else # default to smtp
          Mailer::SMTPMailer.setup
          Mailer::SMTPMailer.new(from, from_name)
        end
      end
    end

    # Reset the mailer (useful for testing)
    def self.reset_mailer
      @mailer = nil
    end
  end
end
