# apps/api/v2/logic/feedback.rb

require_relative 'base'

module V2
  module Logic
    class ReceiveFeedback < V2::Logic::Base
      attr_reader :msg, :greenlighted, :tz, :version

      def process_params
        @msg = params[:msg].to_s.slice(0, 999)
        @tz = params[:tz].to_s.slice(0, 64)
        @version = params[:version].to_s.slice(0, 32)
      end

      def raise_concerns
        raise_form_error 'You can be more original than that!' if @msg.empty?
      end

      def process
        @greenlighted = true
        @msg = format_feedback_message
        OT.ld [:receive_feedback, msg].inspect

        begin
          configured_colonels = OT.conf.dig('site', 'authentication', 'colonels') || []
          OT.ld "[ReceiveFeedback] Configured colonels #{configured_colonels.inspect}"

          first_colonel = nil
          configured_colonels.each do |colonel_email|
            OT.ld "Colonel: #{colonel_email}"
            first_colonel = V2::Customer.find colonel_email
            next unless first_colonel

            OT.ld "[receive_feedback] Sending feedback to colonel: #{colonel_email} #{first_colonel}"
            send_feedback first_colonel, msg
            break
          end
        rescue StandardError => e
          # We liberally rescue all StandError exceptions here because we don't
          # want to fail the user's feedback submission if we can't send an email.
          OT.le "Error sending feedback email to first colonel: #{e.message}", e.backtrace
        end

        V2::Feedback.add @msg
      end

      def format_feedback_message
        identifier = cust.anonymous? ? sess.ipaddress : cust.custid
        "#{msg} [#{identifier}] [TZ: #{tz}] [v#{version}]"
      end
      private :format_feedback_message

      def success_data
        {
          success: greenlighted,
          record: {},
          details: {
            message: 'Message received. Send as much as you like!',
          },
        }
      end

      def send_feedback(cust, message)
        view = Onetime::Mail::FeedbackEmail.new cust, locale
        view.display_domain = display_domain
        view.domain_strategy = domain_strategy
        view.message = message

        OT.ld "[send_feedback] Calling deliver_email (#{message.size} chars)"

        begin
          view.deliver_email
        rescue StandardError => e
          OT.le "Error sending feedback email: #{e.message}", e.backtrace
          # No need to notify the user of this error. The message is still
          # saved in Redis and available via the colonel interface.
        end
      end
    end
  end
end
