# lib/onetime/mail/choose.rb

require_relative 'mailer/base_mailer'
require_relative 'mailer/smtp_mailer'
require_relative 'mailer/sendgrid_mailer'
require_relative 'mailer/ses_mailer'

module Onetime
  module Mail
    module Choose

      # Returns the configured mailer instance
      def self.mailer
        @mailer ||= begin
          provider = OT.conf[:emailer][:provider] || 'smtp'
          from = OT.conf[:emailer][:from]
          fromname = OT.conf[:emailer][:fromname]

          case provider.to_s.downcase
          when 'sendgrid'
            SendGridMailer.setup
            SendGridMailer.new(from, fromname)
          when 'amazon_ses'
            SESMailer.setup
            SESMailer.new(from, fromname)
          else # default to smtp
            SMTPMailer.setup
            SMTPMailer.new(from, fromname)
          end
        end
      end

      # Reset the mailer (useful for testing)
      def self.reset_mailer
        @mailer = nil
      end

    end
  end

  # Load all email templates
  Dir.glob(File.join(File.dirname(__FILE__), 'mail', '*.rb')).each do |file|
    require file unless file =~ /\/(base|smtp|sendgrid|amazon_ses)_mailer\.rb$/
  end
end
