# frozen_string_literal: true

# warn_indent: true

require 'mustache'

class Mustache
  self.template_extension = 'html'

  def self.partial(name)
    path = "#{template_path}/#{name}.#{template_extension}"
    if Otto.env?(:dev)
      File.read(path)
    else
      @_partial_cache ||= {}
      @_partial_cache[path] ||= File.read(path)
      @_partial_cache[path]
    end
  end
end

module Onetime
  class App

    require_relative 'views/base'

    module Views
      class Homepage < Onetime::App::View
        include CreateSecretElements
        def init *args
          self[:title] = "Share a secret"
          self[:with_analytics] = false
        end
      end

      class Incoming < Onetime::App::View
        include CreateSecretElements
        def init *args
          self[:title] = "Share a secret"
          self[:with_analytics] = false
          self[:incoming_recipient] = OT.conf[:incoming][:email]
          self[:display_feedback] = false
          self[:display_masthead] = self[:display_links] = false
        end
      end

      module Docs
        class Api < Onetime::App::View
          def init *args
            self[:title] = "API Docs"
            self[:subtitle] = "OTS Developers"
            self[:with_analytics] = false
            self[:css] << '/css/docs.css'
          end
          def baseuri_httpauth
            scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
            [scheme, 'USERNAME:APITOKEN@', Onetime.conf[:site][:host]].join
          end
        end
        class Api < Onetime::App::View
          class Secrets < Api
          end
          class Libs < Api
          end
        end
      end

      module Meta
        # The robots.txt file
        class Robot < Onetime::App::View
        end
      end

      module Info
        class Privacy < Onetime::App::View
          def init *args
            self[:title] = "Privacy Policy"
            self[:with_analytics] = false
          end
        end

        class Security < Onetime::App::View
          def init *args
            self[:title] = "Security Policy"
            self[:with_analytics] = false
          end
        end

        class Terms < Onetime::App::View
          def init *args
            self[:title] = "Terms and Conditions"
            self[:with_analytics] = false
          end
        end
      end

      class UnknownSecret < Onetime::App::View
        def init
          self[:title] = "No such secret"
          self[:display_feedback] = false
        end
      end

      class Shared < Onetime::App::View
        def init
          self[:title] = "You received a secret"
          self[:body_class] = :generate
          self[:display_feedback] = false
          self[:display_sitenav] = false
          self[:display_links] = false
          self[:display_masthead] = false
          self[:no_cache] = true
        end
        def display_lines
          v = self[:secret_value].to_s
          ret = ((80+v.size)/80) + (v.scan(/\n/).size) + 3
          ret = ret > 30 ? 30 : ret
        end
        def one_liner
          v = self[:secret_value].to_s
          v.scan(/\n/).size.zero?
        end
      end

      class Private < Onetime::App::View
        def init metadata
          self[:title] = "You saved a secret"
          self[:body_class] = :generate
          self[:metadata_key] = metadata.key
          self[:metadata_shortkey] = metadata.shortkey
          self[:secret_key] = metadata.secret_key
          self[:secret_shortkey] = metadata.secret_shortkey
          self[:recipients] = metadata.recipients
          self[:display_feedback] = false
          self[:no_cache] = true
          # Metadata now lives twice as long as the original secret.
          # Prior to the change they had the same value so we can
          # default to using the metadata ttl.
          ttl = (metadata.secret_ttl || metadata.ttl).to_i
          self[:created_date_utc] = epochformat(metadata.created.to_i)
          self[:expiration_stamp] = if ttl <= 1.minute
            '%d seconds' % ttl
          elsif ttl <= 1.hour
            '%d minutes' % ttl.in_minutes
          elsif ttl <= 1.day
            '%d hours' % ttl.in_hours
          else
            '%d days' % ttl.in_days
          end
          secret = metadata.load_secret
          if secret.nil?
            self[:is_received] = metadata.state?(:received)
            self[:is_burned] = metadata.state?(:burned)
            self[:is_destroyed] = self[:is_burned] || self[:is_received]
            self[:received_date] = natural_time(metadata.received.to_i || 0)
            self[:received_date_utc] = epochformat(metadata.received.to_i || 0)
            self[:burned_date] = natural_time(   metadata.burned.to_i || 0)
            self[:burned_date_utc] = epochformat(metadata.burned.to_i || 0)
          else
            self[:maxviews] = secret.maxviews
            self[:has_maxviews] = true if self[:maxviews] > 1
            self[:view_count] = secret.view_count
            if secret.viewable?
              self[:has_passphrase] = !secret.passphrase.to_s.empty?
              self[:can_decrypt] = secret.can_decrypt?
              self[:secret_value] = secret.decrypted_value if self[:can_decrypt]
              self[:truncated] = secret.truncated
            end
          end
          self[:show_secret] = !secret.nil? && !(metadata.state?(:viewed) || metadata.state?(:received) || metadata.state?(:burned))
          self[:show_secret_link] = !(metadata.state?(:received) || metadata.state?(:burned)) && (self[:show_secret] || metadata.owner?(cust)) && self[:recipients].nil?
          self[:show_metadata_link] = metadata.state?(:new)
          self[:show_metadata] = !metadata.state?(:viewed) || metadata.owner?(cust)

          domain = if self[:domains_enabled]
            metadata.share_domain || site_host
          else
            site_host
          end

          self[:share_domain] = [base_scheme, domain].join
        end

        def share_path
          [:secret, self[:secret_key]].join('/')
        end
        def burn_path
          [:private, self[:metadata_key], 'burn'].join('/')
        end
        def metadata_path
          [:private, self[:metadata_key]].join('/')
        end
        def share_uri
          [baseuri, share_path].flatten.join('/')
        end
        def metadata_uri
          [baseuri, metadata_path].flatten.join('/')
        end
        def burn_uri
          [baseuri, burn_path, 'burn'].flatten.join('/')
        end
        def display_lines
          ret = self[:secret_value].to_s.scan(/\n/).size + 2
          ret = ret > 20 ? 20 : ret
        end
        def one_liner
          self[:secret_value].to_s.scan(/\n/).size.zero?
        end
      end

      class Burn < Onetime::App::View
        def init metadata
          self[:title] = "You saved a secret"
          self[:body_class] = :generate
          self[:metadata_key] = metadata.key
          self[:metadata_shortkey] = metadata.shortkey
          self[:secret_key] = metadata.secret_key
          self[:secret_shortkey] = metadata.secret_shortkey
          self[:state] = metadata.state
          self[:recipients] = metadata.recipients
          self[:display_feedback] = false
          self[:no_cache] = true
          self[:show_metadata] = !metadata.state?(:viewed) || metadata.owner?(cust)
          secret = metadata.load_secret
          ttl = metadata.ttl.to_i  # the real ttl is always a whole number
          self[:expiration_stamp] = if ttl <= 1.minute
            '%d seconds' % ttl
          elsif ttl <= 1.hour
            '%d minutes' % ttl.in_minutes
          elsif ttl <= 1.day
            '%d hours' % ttl.in_hours
          else
            '%d days' % ttl.in_days
          end
          if secret.nil?
            self[:is_received] = metadata.state?(:received)
            self[:is_burned] = metadata.state?(:burned)
            self[:is_destroyed] = self[:is_burned] || self[:is_received]
            self[:received_date] = natural_time(metadata.received.to_i || 0)
            self[:received_date_utc] = epochformat(metadata.received.to_i || 0)
            self[:burned_date] = natural_time(   metadata.burned.to_i || 0)
            self[:burned_date_utc] = epochformat(metadata.burned.to_i || 0)
          else
            if secret.viewable?
              self[:has_passphrase] = !secret.passphrase.to_s.empty?
              self[:can_decrypt] = secret.can_decrypt?
              self[:secret_value] = secret.decrypted_value if self[:can_decrypt]
              self[:truncated] = secret.truncated
            end
          end
        end
        def metadata_uri
          [baseuri, :private, self[:metadata_key]].join('/')
        end
      end

      class Forgot < Onetime::App::View
        def init
          self[:title] = "Forgotten Password"
          self[:body_class] = :login
          self[:with_analytics] = false
        end
      end

      class Signin < Onetime::App::View
        self.pagename = :login # used for locale content
        def init
          self[:title] = "Sign In"
          self[:body_class] = :login
          self[:with_analytics] = false
          if req.params[:custid]
            add_form_fields :custid => req.params[:custid]
          end
          if sess.authenticated?
            add_message "You are already logged in."
          end
        end
      end

      class Signup < Onetime::App::View
        def init
          self[:title] = "Create an account"
          self[:body_class] = :signup
          self[:with_analytics] = false
          planid = req.params[:planid]
          planid = 'individual_v1' unless OT::Plan.plan?(planid)
          self[:planid] = planid
          plan = OT::Plan.plan(self[:planid])
          self[:plan] = {
            :price => plan.price.zero? ? 'Free' : plan.calculated_price,
            :original_price => plan.price.to_i,
            :ttl => plan.options[:ttl].in_days.to_i,
            :size => plan.options[:size].to_bytes.to_i,
            :api => plan.options[:api].to_s == 'true',
            :name => plan.options[:name],
            :private => plan.options[:private].to_s == 'true',
            :cname => plan.options[:cname].to_s == 'true',
            :is_paid => plan.paid?,
            :planid => self[:planid]
          }
          setup_plan_variables
        end
      end

      class Pricing < Onetime::App::View
        def init
          self[:title] = "Create an Account"
          self[:body_class] = 'entrypoint/main-full-width'
          self.pagename = 'entrypoint/main-full-width.html'
          setup_plan_variables
        end
        def plan1;  self[@plans[0].to_s]; end
        def plan2;  self[@plans[1].to_s]; end
        def plan3;  self[@plans[2].to_s]; end
        def plan4;  self[@plans[3].to_s]; end
      end

      class Dashboard < Onetime::App::View
        include CreateSecretElements
        def init
          self[:title] = "Your Dashboard"
          self[:body_class] = :dashboard
          self[:with_analytics] = false
          self[:metadata] = cust.metadata.collect do |m|
            { :uri => private_uri(m),
              :stamp => natural_time(m.updated),
              :updated => epochformat(m.updated),
              :key => m.key,
              :shortkey => m.key.slice(0,8),
              # Backwards compatible for metadata created prior to Dec 5th, 2014 (14 days)
              :secret_shortkey => m.secret_shortkey.to_s.empty? ? nil : m.secret_shortkey,
              :recipients => m.recipients,
              :is_received => m.state?(:received),
              :is_burned => m.state?(:burned),
              :is_destroyed => (m.state?(:received) || m.state?(:burned))}
          end.compact
          self[:received],self[:notreceived] =
            *self[:metadata].partition{ |m| m[:is_destroyed] }
          self[:received].sort!{ |a,b| b[:updated] <=> a[:updated] }
          self[:has_secrets] = !self[:metadata].empty?
          self[:has_received] = !self[:received].empty?
          self[:has_notreceived] = !self[:notreceived].empty?
        end
      end

      class Recent < Onetime::App::Views::Dashboard
        # Use the same locale as the dashboard
        self.pagename = :dashboard # used for locale content
      end

      class DashboardComponent < Onetime::App::Views::Dashboard
        self.pagename = :dashboard
        def initialize component, req, sess=nil, cust=nil, locale=nil, *args
          @vue_component_name = component
          super req, sess, cust, locale, *args
        end
      end

      class Account < Onetime::App::View
        def init
          self[:title] = "Your Account"
          self[:body_class] = :account
          self[:with_analytics] = false
          self[:price] = plan.calculated_price
          self[:is_paid] = plan.paid?
          self[:customer_since] = epochdom(cust.created)
          self[:contributor] = cust.contributor?
          if self[:contributor]
            self[:contributor_since] = epochdate(cust.contributor_at)
          end

          if self[:colonel]
            if cust.passgen_token.nil?
              cust.update_passgen_token sess.sessid.gibbler
            end
            self[:token] = cust.passgen_token
          end

          self[:jsvars] << jsvar(:apitoken, cust.apitoken) # apitoken/apikey confusion
        end
      end

      class Error < Onetime::App::View
        def init *args
          self[:title] = "Oh cripes!"
        end
      end

      class About < Onetime::App::View
        def init *args
          self[:title] = "About Us"
          self[:body_class] = :info
          self[:with_analytics] = false
          setup_plan_variables
        end
      end

      @translations = nil
      class Translations < Onetime::App::View
        TRANSLATIONS_PATH = File.join(OT::HOME, 'etc', 'translations.yaml')
        class << self
          attr_accessor :translations  # class instance variable
        end
        def init *args
          self[:title] = "Help us translate"
          self[:body_class] = :info
          self[:with_analytics] = false
          # Load translations YAML file from etc/translations.yaml
          self.class.translations ||= OT::Config.load(TRANSLATIONS_PATH)
          self[:translations] = self.class.translations
        end
      end

      class NotFound < Onetime::App::View
        def init *args
          self[:title] = "Page not found"
          self[:body_class] = :info
          self[:with_analytics] = false
        end
      end

      class Feedback < Onetime::App::View
        def init *args
          self[:title] = "Your Feedback"
          self[:body_class] = :info
          self[:with_analytics] = false
          self[:display_feedback] = false
          #self[:popular_feedback] = OT::Feedback.popular.collect do |k,v|
          #  {:msg => k, :stamp => natural_time(v) }
          #end
        end
      end
    end
  end
end
