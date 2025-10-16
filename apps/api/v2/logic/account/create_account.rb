module V2::Logic
  module Account
    class CreateAccount < V2::Logic::Base
      attr_reader :cust, :autoverify, :customer_role, :planid, :email, :password, :skill
      attr_accessor :token

      def process_params
        OT.ld "[CreateAccount#process_params] param keys: #{params.keys.sort}"
        @planid = params[:planid].to_s

        # NOTE: The parameter names should match what rodauth uses.
        @email = params[:login].to_s.downcase.strip
        @password = self.class.normalize_password(params[:password])

        autoverify_setting = site.dig('authentication', 'autoverify')
        @autoverify        = autoverify_setting.to_s.eql?('true') || false

        # This is a hidden field, so it should be empty. If it has a value, it's
        # a simple bot trying to submit the form or similar chicanery. We just
        # quietly redirect to the home page to mimic a successful response.
        @skill = params[:skill].to_s.strip.slice(0, 60)
      end

      def raise_concerns
        raise OT::FormError, "You're already signed up" if @strategy_result.authenticated?

        raise_form_error 'Please try another email address', field: 'login', error_type: 'already_exists' if Onetime::Customer.email_exists?(email)
        raise_form_error 'Is that a valid email address?', field: 'login', error_type: 'invalid' unless valid_email?(email)
        raise_form_error 'Password is too short', field: 'password', error_type: 'too_short' unless password.size >= 6

        @planid ||= 'basic'

        # Quietly redirect suspected bots to the home page.
        return if skill.empty?

        raise OT::Redirect.new('/?s=1') # the query string is arbitrary, for log filtering
      end

      def process
        @cust = Onetime::Customer.create!(email: email)

        cust.update_passphrase password

        colonels       = OT.conf.dig('site', 'authentication', 'colonels')
        @customer_role = if colonels&.member?(cust.custid)
                           'colonel'
                         else
                           'customer'
                         end

        cust.planid    = planid
        cust.verified  = @autoverify.to_s
        cust.role      = @customer_role.to_s
        cust.save

        session_id = @strategy_result.session[:id] || 'unknown'
        ip_address = @strategy_result.metadata[:ip] || 'unknown'
        OT.info "[new-customer] #{cust.objid} #{cust.role} #{ip_address} #{planid} #{session_id}"

        success_message = if autoverify
                            'Account created. Please sign in.'
                          else
                            # TODO: Disable mail verification temporarily on feature/1787-dual-auth-modes branch
                            # send_verification_email

                            # NOTE: Intentionally left as symbols for i18n keys
                            "#{i18n.dig(:web, :COMMON, :verification_sent_to)} #{cust.custid}."
                          end

        @sess['success_message'] = success_message
      end

      private

      def form_fields
        { planid: planid, email: email }
      end
    end
  end
end
