# .purgatory/lib-onetime-mail/views/base.rb
#
# frozen_string_literal: true

require 'chimera'

require 'v1/refinements'

module Onetime
  module Mail
    module Views
      class Base < Chimera
        using V1::IndifferentHashAccess

        self.template_path  = './templates/mail'
        self.view_namespace = Onetime::Mail
        self.view_path      = './onetime/email'

        attr_reader :cust, :locale, :emailer, :mode, :from, :to
        attr_accessor :token, :text_template

        def initialize(cust, locale, *)
          @cust   = cust
          @locale = locale

          # We quietly continue if we're given an unknown locale and continue
          # with the default. This avoids erroring out when sending an email
          # for example which we don't have a proper UX to handle letting the
          # user know that the email was not sent yet (and then having a way
          # to retry sending the email).
          if OT.locales.key?(locale)
            OT.ld "Initializing #{self.class} with locale: #{locale}"
          else
            default_value = OT.default_locale
            @locale       = default_value
            available     = OT.supported_locales
            OT.le "[views.i18n] Locale not found: #{locale} (continuing with #{default_value} / #{available})"
          end

          OT.ld "#{self.class} locale is: #{locale}"

          conf = OT.conf.fetch('emailer', {})

          @mode = conf.fetch('mode', 'smtp').to_s.to_sym

          # Create a new instance of the configured mailer class for this request
          @emailer = OT.emailer.new(
            conf.fetch('from', nil),
            conf.fetch('fromname', nil),
            cust&.email, # use for the reply-to field
          )

          password_is_present = conf.fetch('pass', nil).to_s.length.positive?
          logsafe_config      = {
            'from' => conf.fetch('from', nil),
            'fromname' => conf.fetch('fromname', nil),
            'host' => conf.fetch('host', nil),
            'port' => conf.fetch('port', nil),
            'user' => conf.fetch('user', nil),
            'tls' => conf.fetch('tls', nil),
            'auth' => conf.fetch('auth', nil), # auth type
            'region' => conf.fetch('region', nil),
            'pass' => "has password: #{password_is_present}",
            'locale' => locale.to_s,
          }

          OT.info "[mailer] #{mode} #{logsafe_config.to_json}"
          init(*) if respond_to? :init
        end

        # Retrieves internationalization data for the current view context.
        #
        # This method implements locale-aware caching:
        #   1. Each locale has its own cache entry to prevent cross-locale contamination
        #   2. The first request for a locale builds and stores the i18n data
        #   3. Subsequent requests for the same locale use the cached data
        #
        # Also handles the following cases:
        #   - If this instance doesn't have a locale yet, we'll use the default locale.
        #   - If the configured default_locale data is missing, returns english data
        #
        # @note TESTING CONSIDERATIONS:
        #   Without per-locale caching, tests can fail intermittently due to:
        #   - Test order dependency: If a test with valid locale runs first, the method
        #     memoizes valid data and subsequent tests pass regardless of locale validity
        #   - If a test with invalid locale runs first, the method fails and doesn't cache
        #     data, causing inconsistent behavior
        #   - RSpec's randomized execution order means these failures appear intermittent
        #
        # @return [Hash] Structured hash containing locale-specific content:
        #   - :locale [String] The resolved locale code
        #   - :email [Hash] Email template content for the current page
        #   - :COMMON [Hash] Common web text elements
        #
        def i18n
          @i18n_cache ||= {}
          locale        = self.locale # || OT.default_locale || 'en'

          # Return cached value for this specific locale if it exists
          return @i18n_cache[locale] if @i18n_cache.key?(locale)

          # Safely get locale data with fallback
          locale_data = OT.locales[locale] || OT.locales['en']

          pagename = self.class.name.split('::').last.downcase.to_s
          {
            locale: locale,
            email: locale_data[:email][pagename],
            COMMON: locale_data[:web][:COMMON],
          }
        end

        def deliver_email(token = nil)
          errmsg = "Your message wasn't sent because we have an email problem"

          email_address_obscured = OT::Utils.obscure_email self[:email_address]
          OT.info "Emailing/#{self.token} #{email_address_obscured} [#{self.class}]"

          message_identifier = if self[:secret]
                      self[:secret].identifier
                    else
                      SecureRandom.hex.to_s[0, 24]
                    end

          mailer_response = begin
            # If we have a token of gratitude, we skip the email. There is only one
            # codepath that has a token set. Just keep in mind that this is not an
            # authentication token or any kind of unique value. It's just a simple
            # flag that when set to any truthy value will skip over this delivery.
            # See V1::API#create
            unless token
              emailer.send_email self[:email_address], subject, render_html, render_text
            end
          rescue SocketError => ex
          internal_emsg   = "Cannot send mail: #{ex.message}\n#{ex.backtrace}"
          OT.le internal_emsg

          raise OT::Problem, errmsg
          rescue Exception => ex
            internal_emsg = "Cannot send mail: #{ex.message}\n#{ex.backtrace}"
            OT.le internal_emsg
            OT.le errmsg

            raise OT::Problem, errmsg
          end

          # Nothing left to do here if we didn't send an email
          return unless mailer_response

          OT.info "[email-sent] to #{email_address_obscured} #{self[:cust].identifier} #{message_identifier}"
          mailer_response
        end

        def render_html
          render
        end

        def render_text
          clone                     = self.clone
          # Create a new options hash if none exists, or duplicate the existing one
          opts                      = clone.instance_variable_get(:@options)
          opts                      = opts ? opts.dup : {}
          # Set template extension
          opts[:template_extension] = 'txt'
          # Update the options in the cloned instance
          clone.instance_variable_set(:@options, opts)
          clone.render
        end

        def receipt_uri(obj)
          format('/receipt/%s', obj.key)
        end
        alias private_uri receipt_uri
        def secret_uri(obj)
          format('/secret/%s', obj.key)
        end

        def secret_display_domain(obj)
          scheme = base_scheme
          host   = obj.share_domain || Onetime.conf['site']['host']
          [scheme, host].join
        end

        def base_scheme
          Onetime.conf['site']['ssl'] ? 'https://' : 'http://'
        end

        def baseuri
          scheme = base_scheme
          host   = Onetime.conf['site']['host']
          [scheme, host].join
        end
      end
    end
  end
end
