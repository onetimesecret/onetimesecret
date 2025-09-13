# apps/api/v2/logic/meta.rb

require_relative 'base'
require_relative 'feedback'

module V2
  module Logic
    module Meta
      # Static methods that return system information
      def self.get_supported_locales(req, res)
        supported_locales = OT.supported_locales.map(&:to_s)
        default_locale = OT.default_locale
        {
          success: true,
          locales: supported_locales,
          default_locale: default_locale,
          locale: default_locale
        }
      end

      def self.system_status(req, res)
        {
          success: true,
          status: :nominal,
          locale: OT.default_locale
        }
      end

      def self.system_version(req, res)
        {
          success: true,
          version: OT::VERSION.to_a,
          locale: OT.default_locale
        }
      end

      # Instance-based Logic classes for stateful operations
      class Authcheck < V2::Logic::Base
        def raise_concerns; end

        def process
          # This logic is handled automatically by Otto's auth strategies
        end

        def success_data
          {
            record: cust.safe_dump,
            details: { authenticated: !cust.anonymous? }
          }
        end
      end

      class GetValidateShrimp < V2::Logic::Base
        attr_reader :is_valid, :shrimp_value

        def process_params
          @shrimp_value = params[:shrimp] || req&.env&.dig('HTTP_O_SHRIMP').to_s
        end

        def raise_concerns
          # Allow empty shrimp - we'll generate a new one
        end

        def process
          OT.ld "[Debug-Shrimp] Validating shrimp: #{@shrimp_value}"

          begin
            @is_valid = !@shrimp_value.empty? && validate_shrimp(@shrimp_value, false)
          rescue OT::BadShrimp => ex
            OT.ld "BadShrimp exception: #{ex.message}"
            @is_valid = false
          end

          sess.replace_shrimp! unless @is_valid
        end

        def success_data
          {
            isValid: @is_valid,
            shrimp: sess.shrimp
          }
        end

        private

        def validate_shrimp(shrimp, strict = true)
          # Implementation would need to be copied from the controller base
          # For now, return false to trigger shrimp regeneration
          false
        end
      end

      # Alias for backwards compatibility
      ReceiveFeedback = V2::Logic::ReceiveFeedback
    end
  end
end
