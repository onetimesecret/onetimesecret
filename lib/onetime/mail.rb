# lib/onetime/mail.rb

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
        provider = OT.conf[:emailer][:provider] || 'smtp'
        from = OT.conf[:emailer][:from]
        fromname = OT.conf[:emailer][:fromname]

        case provider.to_s.downcase
        when 'sendgrid'
          Mailer::SendGridMailer.setup
          Mailer::SendGridMailer.new(from, fromname)
        when 'ses'
          Mailer::SESMailer.setup
          Mailer::SESMailer.new(from, fromname)
        else # default to smtp
          Mailer::SMTPMailer.setup
          Mailer::SMTPMailer.new(from, fromname)
        end
      end
    end

    # Reset the mailer (useful for testing)
    def self.reset_mailer
      @mailer = nil
    end
  end
end
