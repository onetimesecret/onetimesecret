# apps/api/v2/logic/exceptions.rb

require_relative 'base'

module V2::Logic
  # Handles incoming exception reports similar to Sentry's basic functionality
  class ReceiveException < V2::Logic::Base

    attr_reader :exception_data, :environment, :release, :greenlighted, :exception, :exception_key

    def process_params
      @exception_data = {
        message: params[:message].to_s.slice(0, 256),
        type: params[:type].to_s.slice(0, 100),
        stack: params[:stack].to_s.slice(0, 2500),
        url: params[:url].to_s.slice(0, 256),
        line: params[:line].to_i,
        column: params[:column].to_i,
        timestamp: Time.now.utc.iso8601,
        user_agent: params[:user_agent].to_s.slice(0, 100),
        # Context data
        environment: params[:environment].to_s.slice(0, 50) || 'production',
        release: params[:release].to_s.slice(0, 50),
        user: cust.anonymous? ? sess.ipaddress : cust.custid,
      }.compact
    end

    def raise_concerns
      raise_form_error 'Exception data required' if @exception_data[:message].empty?

      limit_action :report_exception

      # Also limit by error specific type/location
      limit_action "exception:#{@exception_data[:type]}:#{@exception_data[:url]}"
    end

    # Updated ReceiveException process method
    def process
      @greenlighted = true

      # Create new exception record
      OT.ld('[Exception] Creating new exception record')
      @exception = V2::ExceptionInfo.new
      OT.ld('[Exception] Applying exception data', @exception_data)
      exception.apply_fields(**@exception_data)
      exception.save

      # Add to sortable index
      V2::ExceptionInfo.add(exception)

      # Log critical errors
      if @exception_data[:type]&.include?('Error')
        OT.le "[Exception] #{exception.type}: #{exception.message} " \
              "URL: #{exception.url} User: #{exception.user}"
      end

      @exception_key = exception.identifier
    end


    def success_data
      {
        success: greenlighted,
        record: exception.safe_dump,
        details: {
          message: 'Exception logged',
        },
      }
    end

  end
end
