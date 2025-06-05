# lib/onetime/initializers/setup_emailers.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    module SetupEmailers

      using IndifferentHashAccess

      def self.run(options = {})
        mail_mode = OT.conf[:emailer][:mode].to_s.to_sym

        mailer_class = case mail_mode
        when :sendgrid
          Onetime::Mail::Mailer::SendGridMailer
        when :ses
          Onetime::Mail::Mailer::SESMailer
        when :smtp
          Onetime::Mail::Mailer::SMTPMailer
        else
          OT.le "Unsupported mail mode: #{mail_mode}, falling back to SMTP"
          Onetime::Mail::Mailer::SMTPMailer
        end

        mailer_class.setup
        OT.instance_variable_set(:@emailer, mailer_class)
        OT.ld "[initializer] Emailer prepared (mode: #{mail_mode})"
      end

    end
  end
end
