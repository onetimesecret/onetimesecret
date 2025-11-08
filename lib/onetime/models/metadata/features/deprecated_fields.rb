# lib/onetime/models/metadata/features/deprecated_fields.rb
#
# frozen_string_literal: true

module Onetime::Metadata::Features
  module DeprecatedFields
    Familia::Base.add_feature self, :deprecated_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      base.field_group :deprecated_fields do
        base.field :key
        base.field :viewed, fast_method: false
        base.field :received, fast_method: false
        base.field :shared, fast_method: false
        base.field :burned, fast_method: false
        base.field :custid
        base.field :truncate # boolean
        base.field :secret_key # use secret_identifier
      end
    end

    module ClassMethods

    end

    module InstanceMethods

      def deliver_by_email(cust, locale, secret, eaddrs, template = nil, ticketno = nil)
        template ||= Onetime::Email::SecretLink

        if eaddrs.nil? || eaddrs.empty?
          secret_logger.info "No email addresses specified for delivery", {
            metadata_id: identifier,
            secret_id: secret.identifier,
            user: cust.obscure_email,
            action: 'deliver_email'
          }
          return
        end

        secret_logger.debug "Preparing email delivery", {
          metadata_id: identifier,
          secret_id: secret.identifier,
          user: cust.obscure_email,
          token: token.nil? ? nil : 'present',
          action: 'deliver_email'
        }

        eaddrs = [eaddrs].flatten.compact[0..9] # Max 10

        eaddrs_safe     = eaddrs.collect { |e| OT::Utils.obscure_email(e) }
        eaddrs_safe_str = eaddrs_safe.join(', ')

        secret_logger.info "Delivering secret by email", {
          metadata_id: identifier,
          secret_id: secret.identifier,
          user: cust.obscure_email,
          recipient_count: eaddrs_safe.size,
          recipients: eaddrs_safe_str,
          action: 'deliver_email'
        }
        recipients! eaddrs_safe_str

        if eaddrs.size > 1
          secret_logger.warn "Multiple recipients detected", {
            metadata_id: identifier,
            secret_id: secret.identifier,
            recipient_count: eaddrs.size,
            action: 'deliver_email'
          }
        end

        eaddrs.each do |email_address|
          view                  = template.new cust, locale, secret, email_address
          view.ticketno         = ticketno if ticketno
          view.emailer.reply_to = cust.email
          view.deliver_email token # pass the token from spawn_pair through
          break # force just a single recipient
        end
      end

      # NOTE: We override the default fast writer (bang!) methods from familia
      # so that we can update two fields at once. To replicate the same behavior
      # we pass update_expiration: false to save so that changing this metdata
      # objects state doesn't affect its original expiration time.
      #
      # TODO: Replace with transaction (i.e. MULTI/EXEC command)
      def viewed!
        # A guard to allow only a fresh, new secret to be viewed. Also ensures
        # that we don't support going from viewed back to something else.
        return unless state?(:new)

        self.state  = 'viewed'
        self.viewed = Familia.now.to_i
        # The nuance bewteen being "viewed" vs "received" or "burned" is
        # that the secret link page has been requested (via GET)
        # but the "View Secret" button hasn't been clicked yet (i.e. we haven't
        # yet received the POST request that actually reveals the contents
        # of the secret). It's a subtle but important distinction bc it
        # communicates an amount of activity around the secret. The terminology
        # can be improved though and we'll also want to achieve parity with the
        # API by allowing a GET (or OPTIONS) for the secret as a check that it
        # is still valid -- that should set the state to viewed as well.
        save update_expiration: false

        secret_logger.info "Metadata state transition to viewed", {
          metadata_id: shortid,
          secret_id: secret_identifier,
          previous_state: 'new',
          new_state: 'viewed',
          timestamp: viewed
        }
      end

      def received!
        # A guard to allow only a fresh secret to be received. Also ensures
        # that we don't support going from received back to something else.
        return unless state?(:new) || state?(:viewed)

        previous_state = state
        self.state      = 'received'
        self.received   = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.info "Metadata state transition to received", {
          metadata_id: shortid,
          secret_id: secret_identifier,
          previous_state: previous_state,
          new_state: 'received',
          timestamp: received
        }
      end

      # We use this method in special cases where a metadata record exists with
      # a secret_id value but no valid secret object exists. This can happen
      # when a secret is manually deleted but the metadata record is not. Otherwise
      # it's a bug and although unintentional we want to handle it gracefully here.
      def orphaned!
        # A guard to prevent modifying metadata records that already have
        # cleared out the secret (and that probably have already set a reason).
        return if secret_identifier.to_s.empty?
        return unless state?(:new) || state?(:viewed) # only new or viewed secrets can be orphaned

        previous_state = state
        original_secret_id = secret_identifier
        self.state      = 'orphaned'
        self.updated    = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.warn "Metadata state transition to orphaned", {
          metadata_id: shortid,
          secret_id: original_secret_id,
          previous_state: previous_state,
          new_state: 'orphaned',
          timestamp: updated
        }
      end

      def burned!
        # See guard comment on `received!`
        return unless state?(:new) || state?(:viewed)

        previous_state = state
        self.state      = 'burned'
        self.burned     = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.info "Metadata state transition to burned", {
          metadata_id: shortid,
          secret_id: secret_identifier,
          previous_state: previous_state,
          new_state: 'burned',
          timestamp: burned
        }
      end

      def expired!
        # A guard to prevent prematurely expiring a secret. We only want to
        # expire secrets that are actually old enough to be expired.
        return unless secret_expired?

        previous_state = state
        self.state      = 'expired'
        self.updated    = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.info "Metadata state transition to expired", {
          metadata_id: shortid,
          secret_id: secret_identifier,
          previous_state: previous_state,
          new_state: 'expired',
          timestamp: updated,
          secret_ttl: secret_ttl,
          age_seconds: age
        }
      end

      def state?(guess)
        state.to_s == guess.to_s
      end

      def truncated?
        truncate.to_s == 'true'
      end

    end
  end
end
