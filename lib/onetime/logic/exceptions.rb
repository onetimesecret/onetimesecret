# frozen_string_literal: true

require_relative 'base'

module Onetime::Logic
  module Misc
    # Handles incoming exception reports similar to Sentry's basic functionality
    class ReceiveException < OT::Logic::Base
      prefix :exception
      ttl 30.days # Keep exceptions for 30 days

      attr_reader :exception_data, :environment, :release, :greenlighted

      def process_params
        @exception_data = {
          message: params[:message].to_s.slice(0, 1000),
          type: params[:type].to_s.slice(0, 100),
          stack: params[:stack].to_s.slice(0, 10000),
          url: params[:url].to_s.slice(0, 1000),
          line: params[:line].to_i,
          column: params[:column].to_i,
          timestamp: Time.now.utc.iso8601,
          user_agent: params[:user_agent].to_s.slice(0, 500),
          # Context data
          environment: params[:environment].to_s.slice(0, 50) || 'production',
          release: params[:release].to_s.slice(0, 50),
          user: cust.anonymous? ? sess.ipaddress : cust.custid
        }.compact
      end

      def raise_concerns
        limit_action :report_exception
        raise_form_error "Exception data required" if @exception_data[:message].empty?

        # Rate limit by error type/location to prevent spam
        key = "#{@exception_data[:type]}:#{@exception_data[:url]}"
        limit_key = OT::RateLimit.incr! sess.external_identifier, "exception:#{key}"
      end


      # Updated ReceiveException process method
      def process
        @greenlighted = true

        # Create new exception record
        exception = OT::ExceptionInfo.new
        exception.apply_fields(**@exception_data)
        exception.save

        # Add to sortable index
        OT::ExceptionInfo.add(exception)

        # Log critical errors
        if @exception_data[:type]&.include?('Error')
          OT.le "[Exception] #{exception.type}: #{exception.message} "\
                "URL: #{exception.url} User: #{exception.user}"
        end

        @exception_key = exception.identifier
      end


      def success_data
        {
          success: greenlighted,
          record: {
            exception_id: exception_key
          },
          details: {
            message: "Exception logged"
          }
        }
      end

      # Query methods for exception data
      class << self
        def recent(env='production', limit=100)
          redis.zrevrange("exceptions:#{env}", 0, limit-1).map do |key|
            redis.hgetall(key)
          end.compact
        end

        def by_type(type, env='production', limit=100)
          recent(env, 1000).select { |ex| ex['type'] == type }.first(limit)
        end

        def count_by_type(env='production')
          recent(env, 1000).group_by { |ex| ex['type'] }
                          .transform_values(&:count)
        end
      end
    end
  end
end
