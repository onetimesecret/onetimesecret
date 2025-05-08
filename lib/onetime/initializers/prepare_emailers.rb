# lib/onetime/initializers/prepare_emailers.rb

module Onetime
  module Initializers
    attr_reader :emailer

    # Prepares the emailer based on the configured mode.
    #
    # This method retrieves the Redis database configurations from the application
    # settings and establishes connections for each model class within the Familia
    #
    def prepare_emailers
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
      @emailer = mailer_class
    end
  end
end
