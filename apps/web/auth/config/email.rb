# apps/web/auth/config/email.rb
#
# frozen_string_literal: true

module Auth::Config::Email

  def self.configure(auth)

    # Configure Rodauth email settings - use lazy evaluation
    auth.email_from ENV['EMAIL_FROM'] || 'noreply@onetimesecret.com'
    auth.email_subject_prefix ENV['EMAIL_SUBJECT_PREFIX'] || '[OneTimeSecret] '

    # Configure email delivery with lazy initialization
    auth.send_email do |email|
      Onetime.auth_logger.debug 'send_email hook called', {
        subject: email.subject.to_s,
        to: email.to.to_s,
        rack_env: ENV.fetch('RACK_ENV', nil)
      }

      # Deliver email using configured mailer
      mailer = Auth::Mailer::Configuration.new
      mailer.deliver_email(email)
    end

    # Log the provider that will be used without creating the config
    provider = determine_provider_for_logging
    # TODO: Where do we actually use the provider? Probably in Mailer.
    OT.info "[email] Email delivery will use #{provider} provider"
  end

  private_class_method

  def self.determine_provider_for_logging
    mode = ENV['EMAILER_MODE']&.downcase

    if mode.nil?
      if ENV['RACK_ENV'] == 'test'
        'logger'
      elsif ENV['SENDGRID_API_KEY']
        'sendgrid'
      elsif ENV['AWS_ACCESS_KEY_ID'] && ENV['AWS_SECRET_ACCESS_KEY']
        'ses'
      elsif ENV['SMTP_HOST']
        'smtp'
      else
        'logger'
      end
    else
      mode
    end
  end
end
