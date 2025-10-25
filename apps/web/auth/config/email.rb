# apps/web/auth/config/email.rb

module Auth::Config::Email

  def self.configure(auth)

    # Configure Rodauth email settings - use lazy evaluation
    auth.email_from ENV['EMAIL_FROM'] || 'noreply@onetimesecret.com'
    auth.email_subject_prefix ENV['EMAIL_SUBJECT_PREFIX'] || '[OneTimeSecret] '

    # Configure email delivery with lazy initialization
    auth.send_email do |email|
      Onetime.auth_logger.debug 'send_email hook called',
        subject: email.subject.to_s,
        to: email.to.to_s,
        rack_env: ENV.fetch('RACK_ENV', nil)

          def log_delivery(email, status = 'sent', provider = nil)
            provider_info = provider ? " via #{provider}" : ''
            OT.info "[email] #{status.capitalize} email to #{email[:to]}#{provider_info}: #{email[:subject]}"
          end

          def log_error(email, error, provider = nil)
            SemanticLogger['Auth'].error 'Email delivery failed',
              to: email[:to],
              subject: email[:subject],
              provider: provider,
              error: error.message
          end
        end

        class Logger < Base
          def deliver(email)
            puts "\n=== EMAIL DEBUG ==="
            puts 'Provider: Logger'
            puts "To: #{email[:to]}"
            puts "From: #{email[:from]}"
            puts "Subject: #{email[:subject]}"
            puts "Body:\n#{email[:body]}"
            puts "=== END EMAIL ===\n"
            log_delivery(email, 'logged', 'Logger')
          end
        end

        class SMTP < Base
          def deliver(email)
            smtp_host   = @config[:host] || ENV['SMTP_HOST'] || 'localhost'
            smtp_port   = (@config[:port] || ENV['SMTP_PORT'] || '587').to_i
            username    = @config[:username] || ENV.fetch('SMTP_USERNAME', nil)
            password    = @config[:password] || ENV.fetch('SMTP_PASSWORD', nil)
            use_tls     = @config[:tls].nil? ? (ENV['SMTP_TLS'] != 'false') : @config[:tls]
            auth_method = nil # @config[:auth_method] || ENV['SMTP_AUTH'] || 'login'

            message = build_message(email)

            smtp = Net::SMTP.new(smtp_host, smtp_port)
            smtp.enable_starttls_auto if use_tls

            # Handle authentication - only authenticate if username is provided
            if username && password
              begin
                smtp.start(smtp_host, username, password, auth_method) do |smtp_session|
                  smtp_session.send_message(message, email[:from], email[:to])
                end
              rescue Net::SMTPAuthenticationError => ex
                # Server doesn't support authentication - try without auth
                SemanticLogger['Auth'].debug 'SMTP authentication not supported, sending without auth',
                  host: smtp_host,
                  port: smtp_port,
                  error: ex.message

                smtp.start do |smtp_session|
                  smtp_session.send_message(message, email[:from], email[:to])
                end
              end
            else
              smtp.start do |smtp_session|
                smtp_session.send_message(message, email[:from], email[:to])
              end
            end

            log_delivery(email, 'sent', 'SMTP')
          rescue StandardError => ex
            log_error(email, ex, 'SMTP')
            raise ex
          end

          protected

          def validate_config!
            host = @config[:host] || ENV.fetch('SMTP_HOST', nil)
            raise ArgumentError, 'SMTP host must be configured' if host.nil? || host.empty?
          end

          def build_message(email)
            <<~MESSAGE
              From: #{email[:from]}
              To: #{email[:to]}
              Subject: #{email[:subject]}
              Content-Type: text/plain; charset=UTF-8

              #{email[:body]}
            MESSAGE
          end
        end

        class SendGrid < Base
          def deliver(email)
            require 'net/http'
            require 'json'

            api_key = @config[:api_key] || ENV.fetch('SENDGRID_API_KEY', nil)

            payload = {
              personalizations: [{
                to: [{ email: email[:to] }],
                subject: email[:subject],
                to: email[:to],
                exception: ex
              # In production, we might want to queue for retry or use a fallback
              # For now, we'll just log the error
              raise ex unless ENV['RACK_ENV'] == 'production'
            end

          end
        end

      end
    end

    # Log the provider that will be used without creating the config
    # TODO: Where is provider actually used?
    provider = determine_provider_for_logging
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
