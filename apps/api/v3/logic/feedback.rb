# apps/api/v3/logic/feedback.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../../../../lib/onetime/jobs/publisher'

module V3
  module Logic
    class ReceiveFeedback < V3::Logic::Base
      attr_reader :msg, :greenlighted, :tz, :version

      def process_params
        @msg     = sanitize_plain_text(params['msg'], max_length: 999)
        @tz      = sanitize_plain_text(params['tz'], max_length: 64)
        @version = sanitize_plain_text(params['version'], max_length: 32)
      end

      def raise_concerns
        raise_form_error 'You can be more original than that!' if @msg.empty?
      end

      def process
        @greenlighted = true
        @msg          = format_feedback_message
        OT.ld [:receive_feedback, msg].inspect

        begin
          # Find the first colonel in the database to send feedback notification
          # Colonels are managed via CLI: bin/ots role promote email --role colonel
          first_colonel = find_first_colonel
          if first_colonel
            OT.ld "[receive_feedback] Sending feedback to colonel: #{first_colonel.obscure_email}"
            send_feedback first_colonel, msg
          else
            OT.ld '[receive_feedback] No colonels found in database, skipping email notification'
          end
        rescue StandardError => ex
          # We liberally rescue all StandardError exceptions here because we don't
          # want to fail the user's feedback submission if we can't send an email.
          OT.le "Error sending feedback email to first colonel: #{ex.message}", ex.backtrace
        end

        Onetime::Feedback.add @msg

        success_data
      end

      def format_feedback_message
        identifier = cust.anonymous? ? sess.inspect : cust.objid
        "#{msg} [#{identifier}] [TZ: #{tz}] [v#{version}]"
      end
      private :format_feedback_message

      def success_data
        {
          record: {},
          details: {
            message: 'Message received. Send as much as you like!',
          },
        }
      end

      def send_feedback(cust, message)
        OT.ld "[send_feedback] Delivering feedback email (#{message.size} chars)"

        begin
          # Non-critical: feedback is saved in Redis regardless of email
          # Use :none fallback - don't block or spawn threads for notifications
          Onetime::Jobs::Publisher.enqueue_email(
            :feedback_email,
            {
              email_address: cust.email,
              message: message,
              display_domain: display_domain,
              domain_strategy: domain_strategy,
              locale: locale || OT.default_locale,
            },
            fallback: :none,
          )
        rescue StandardError => ex
          OT.le "Error sending feedback email: #{ex.message}", ex.backtrace
          # No need to notify the user of this error. The message is still
          # saved in Redis and available via the colonel interface.
        end
      end

      # Find the first colonel in the database
      # Returns nil if no colonels exist
      # Delegates to Customer.find_first_colonel which uses multi_index
      # for O(1) lookup instead of O(n) scanning all customers.
      def find_first_colonel
        Onetime::Customer.find_first_colonel
      end
      private :find_first_colonel
    end
  end
end
