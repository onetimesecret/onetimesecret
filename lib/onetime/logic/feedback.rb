
require_relative '../../altcha'
require_relative 'base'

module Onetime::Logic
  module Misc

    class ReceiveFeedback < OT::Logic::Base
      attr_reader :msg, :authenticity_payload, :verified, :verification_data, :greenlighted, :tz, :version

      def process_params
        @msg = params[:msg].to_s.slice(0, 999)
        @authenticity_payload = params[:authenticity_payload].to_s.slice(0, 999)
        @tz = params[:tz].to_s.slice(0, 64)
        @version = params[:version].to_s.slice(0, 32)
      end

      def raise_concerns
        limit_action :send_feedback

        raise_form_error "You can be more original than that!" if @msg.empty?

        if cust.anonymous?
          raise_form_error "Cannot skip authenticity check" if authenticity_payload.empty?
          raise_form_error "You need to be carbon-based to do that" unless verify_authenticity_payload
        end
      end

      def verify_authenticity_payload
        @verified = Altcha.verify_solution(authenticity_payload, secret_key)
      end

      def filter_spam_authenticity_payload
        # authenticity_payload is a base64 encoded JSON string.
        @verified, @verification_data = Altcha.verify_server_signature(authenticity_payload, secret_key)

        fields_verified = Altcha.verify_fields_hash(
          params,
          verification_data.fields,
          verification_data.fields_hash,
          'SHA-256'
        )

        verified && fields_verified
      end

      def process
        @greenlighted = true
        @msg = format_feedback_message
        OT.ld [:receive_feedback, msg].inspect


        begin
          configured_colonels = OT.conf[:colonels] || []

          first_colonel = nil
          configured_colonels.each do |colonel_email|
            OT.ld "Colonel: #{colonel_email}"
            first_colonel = OT::Customer.find colonel_email
            if first_colonel
              OT.ld "[receive_feedback] Sending feedback to colonel: #{colonel_email} #{first_colonel}"
              send_feedback first_colonel, msg
              break
            end
          end

        rescue StandardError => ex
          # We liberally rescue all StandError exceptions here because we don't
          # want to fail the user's feedback submission if we can't send an email.
          OT.le "Error sending feedback email to first colonel: #{ex.message}", ex.backtrace
        end

        OT::Feedback.add @msg
      end

      def format_feedback_message
        identifier = cust.anonymous? ? sess.ipaddress : cust.custid
        "#{msg} [#{identifier}] [TZ: #{tz}] [v#{version}]"
      end
      private :format_feedback_message

      def success_data
        {
          success: greenlighted,
          record: {
          },
          details: {
            message: "Message received. Send as much as you like!"
          }
        }
      end

      def secret_key
        OT.conf.dig(:site, :authenticity, :secret_key) # ALTCHA_HMAC_KEY
      end

      def send_feedback cust, message
        view = OT::App::Mail::FeedbackEmail.new cust, locale
        view.display_domain = self.display_domain
        view.domain_strategy = self.domain_strategy
        view.message = message

        OT.ld "[send_feedback] Calling deliver_email #{message.gibbler}"

        begin
          view.deliver_email

        rescue StandardError => ex
          OT.le "Error sending feedback email: #{ex.message}", ex.backtrace
          # No need to notify the user of this error. The message is still
          # saved in Redis and available via the colonel interface.
        end
      end
    end

  end
end
