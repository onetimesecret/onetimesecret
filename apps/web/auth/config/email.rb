# apps/web/auth/config/email.rb

module Auth
  module Config
    module Email
      def self.configure(rodauth_config)
        rodauth_config.instance_eval do
          # Email configuration
          send_email do |email|
            if ENV['RACK_ENV'] == 'production'
              # Use your email delivery service here
              # Example: SendGrid, SES, etc.
              deliver_email_via_service(email)
            else
              # Development: just log emails
              puts "\n=== EMAIL DEBUG ==="
              puts "To: #{email[:to]}"
              puts "Subject: #{email[:subject]}"
              puts "Body:\n#{email[:body]}"
              puts "=== END EMAIL ===\n"
            end
          end
        end
      end

      def self.deliver_email_via_service(email)
        # Example implementation for production email delivery
        # You would replace this with your preferred email service

        case ENV['EMAIL_SERVICE']
        when 'sendgrid'
          deliver_via_sendgrid(email)
        when 'ses'
          deliver_via_ses(email)
        when 'smtp'
          deliver_via_smtp(email)
        else
          # Default: log to file in production
          File.open('log/emails.log', 'a') do |f|
            f.puts "#{Time.now.utc.iso8601}: #{email.inspect}"
          end
        end
      end

      private_class_method def self.deliver_via_sendgrid(email)
        # Implementation for SendGrid
      end

      private_class_method def self.deliver_via_ses(email)
        # Implementation for AWS SES
      end

      private_class_method def self.deliver_via_smtp(email)
        # Implementation for SMTP
      end
    end
  end
end
