
module Onetime
  module App

    module Views

      class Feedback < Onetime::App::View
        self.template_name = :index
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

      class Incoming < Onetime::App::View
        self.template_name = :index
        def init *args
          self[:title] = "Share a secret"
          self[:with_analytics] = false
          self[:incoming_recipient] = OT.conf[:incoming][:email]
          self[:display_feedback] = false
          self[:display_masthead] = self[:display_links] = false
        end
      end

      class Burn < Onetime::App::View
        self.template_name = :index
        def init metadata
          return handle_nil_metadata if metadata.nil?

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
              self[:truncated] = secret.truncated?
            end
          end
        end

        def metadata_url
          [baseuri, :private, self[:metadata_key]].join('/')
        end

        def handle_nil_metadata
          # There are errors in production where metadata is passed in as
          # nil. This temporary logging is to help shed some light.
          #
          # See https://github.com/onetimesecret/onetimesecret/issues/611
          #
          exists = begin
            OT::Metadata.exists?(req.params[:key])
          rescue StandardError => e
            OT.le "[Burn.handle_nil_metadata] Metadata.exists? raised an exception. #{e}"
            nil
          end
          OT.le "[Burn.handle_nil_metadata] Nil metadata passed to view. #{req.path} #{req.params[:key]} exists:#{exists}"
        end
      end

    end
  end
end
