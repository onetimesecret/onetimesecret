

module Onetime::Logic
  module Secrets

    class ShowMetadata < OT::Logic::Base
      # Working variables
      attr_reader :key, :metadata, :secret
      # Template variables
      attr_reader :title, :body_class, :metadata_key, :metadata_shortkey, :secret_key,
            :secret_shortkey, :recipients, :display_feedback, :no_cache,
            :created_date_utc, :expiration_stamp, :is_received, :is_burned,
            :is_destroyed, :received_date, :received_date_utc, :burned_date,
            :burned_date_utc, :maxviews, :has_maxviews, :view_count,
            :has_passphrase, :can_decrypt, :secret_value, :truncated,
            :show_secret, :show_secret_link, :show_metadata_link, :show_metadata,
            :show_recipients, :share_domain
      attr_reader :share_path, :burn_path, :metadata_path, :share_url,
            :metadata_url, :burn_url, :display_lines

      def process_params
        @key = params[:key].to_s
        @metadata = Onetime::Metadata.load key
      end

      def raise_concerns
        limit_action :show_metadata
        raise OT::MissingSecret if metadata.nil?
      end

      def process
        @secret = @metadata.load_secret

        @title = "You saved a secret"
        @body_class = :generate
        @metadata_key = metadata.key
        @metadata_shortkey = metadata.shortkey
        @secret_key = metadata.secret_key
        @secret_shortkey = metadata.secret_shortkey
        @share_domain = metadata.share_domain

        # Default the recipients to an empty string. When a Familia::Horreum
        # object is loaded, the fields that have no values (or that don't
        # exist in the redis hash yet) will have a value of "" (empty string).
        # But for a newly instantiated object, the fields will have a value
        # of nil. Later on, we rely on being able to check for emptiness
        # like: `@recipients.empty?`.
        @recipients = metadata.recipients.to_s

        @display_feedback = false
        @no_cache = true
        # Metadata now lives twice as long as the original secret.
        # Prior to the change they had the same value so we can
        # default to using the metadata ttl.
        ttl = (metadata.secret_ttl || metadata.ttl).to_i
        @created_date_utc = epochformat(metadata.created.to_i)
        @expiration_stamp = if ttl <= 1.minute
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
          @is_received = metadata.state?(:received)
          @is_burned = metadata.state?(:burned)
          @is_destroyed = @is_burned || @is_received
          @received_date = natural_time(metadata.received.to_i || 0)
          @received_date_utc = epochformat(metadata.received.to_i || 0)
          @burned_date = natural_time(metadata.burned.to_i || 0)
          @burned_date_utc = epochformat(metadata.burned.to_i || 0)
        else
          @maxviews = secret.maxviews
          @has_maxviews = true if @maxviews > 1
          @view_count = secret.view_count # TODO: Remove
          if secret.viewable?
            @has_passphrase = !secret.passphrase.to_s.empty?
            @can_decrypt = secret.can_decrypt?
            @secret_value = secret.decrypted_value if @can_decrypt
            @truncated = secret.truncated?
          end
        end

        # Show the secret if it exists and hasn't been seen yet.
        #
        # It will be true if:
        #   1. The secret is not nil (i.e., a secret exists), AND
        #   2. The metadata state is NOT in any of these states: viewed,
        #      received, or burned
        #
        @show_secret = !secret.nil? && !(metadata.state?(:viewed) || metadata.state?(:received) || metadata.state?(:burned))

        # The secret link is shown only when appropriate, considering the
        # state, ownership, and recipient information.
        #
        # It will be true if ALL of these conditions are met:
        #   1. The metadata state is NOT received or burned, AND
        #   2. Either the secret is showable (@show_secret is true) OR
        #      the current customer is the owner of the metadata, AND
        #   3. There are no recipients specified (@recipients is nil)
        #
        @show_secret_link = !(metadata.state?(:received) || metadata.state?(:burned)) &&
                            (@show_secret || metadata.owner?(cust)) &&
                            @recipients.empty?

        # A simple check to show the metadata link only for newly
        # created secrets.
        #
        @show_metadata_link = metadata.state?(:new)

        # Allow the metadata to be shown if it hasn't been viewed yet OR
        # if the current user owns it (regardless of its viewed state).
        #
        # It will be true if EITHER of these conditions are met:
        #   1. The metadata state is NOT 'viewed', OR
        #   2. The current customer is the owner of the metadata
        #
        @show_metadata = !metadata.state?(:viewed) || metadata.owner?(cust)

        # Recipient information is only displayed when the metadata is
        # visible and there are actually recipients to show.
        #
        # It will be true if BOTH of these conditions are met:
        #   1. The metadata should be shown (@show_metadata is true), AND
        #   2. There are recipients specified (@recipients is not empty)
        #
        @show_recipients = @show_metadata && !@recipients.empty?

        domain = if domains_enabled
          if metadata.share_domain.to_s.empty?
            site_host
          else
            metadata.share_domain
          end
        else
          site_host
        end

        @share_domain = [base_scheme, domain].join

        process_uris
      end

      def one_liner
        secret_value.to_s.scan(/\n/).size.zero?
      end

      def success_data
        {
          record: metadata_attributes,
          details: ancillary_attributes
        }
      end

      private

      def process_uris
        @share_path = build_path(:secret, secret_key)
        @burn_path = build_path(:private, metadata_key, 'burn')
        @metadata_path = build_path(:private, metadata_key)
        @share_url = build_url(@share_path)
        @metadata_url = build_url(@metadata_path)
        @burn_url = build_url(@burn_path)

        @display_lines = calculate_display_lines
      end

      def calculate_display_lines
        ret = secret_value.to_s.scan(/\n/).size + 2
        ret > 20 ? 20 : ret
      end

      def metadata_attributes
        {
          key: @metadata_key,
          shortkey: @metadata_shortkey,
          secret_key: @secret_key,
          secret_shortkey: @secret_shortkey,
          recipients: @recipients,
          created_date_utc: @created_date_utc,
          expiration_stamp: @expiration_stamp,
          share_path: @share_path,
          burn_path: @burn_path,
          metadata_path: @metadata_path,
          share_url: @share_url,
          metadata_url: @metadata_url,
          burn_url: @burn_url,
          share_domain: @share_domain
        }
      end

      def ancillary_attributes
        {
          title: @title,
          body_class: @body_class,
          display_lines: @display_lines,
          display_feedback: @display_feedback,
          no_cache: @no_cache,
          is_received: @is_received,
          is_burned: @is_burned,
          is_destroyed: @is_destroyed,
          received_date: @received_date,
          received_date_utc: @received_date_utc,
          burned_date: @burned_date,
          burned_date_utc: @burned_date_utc,
          maxviews: @maxviews,
          has_maxviews: @has_maxviews,
          view_count: @view_count,
          has_passphrase: @has_passphrase,
          can_decrypt: @can_decrypt,
          secret_value: @secret_value,
          truncated: @truncated,
          show_secret: @show_secret,
          show_secret_link: @show_secret_link,
          show_metadata_link: @show_metadata_link,
          show_metadata: @show_metadata,
          show_recipients: @show_recipients
        }
      end

    end


  end
end
