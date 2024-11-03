
module Onetime
  class Metadata < Familia::Horreum
    include Gibbler::Complex

    feature :safe_dump
    feature :expiration

    ttl 14.days
    prefix :metadata

    identifier :generate_id

    field :custid
    field :state
    field :secret_key
    field :secret_shortkey
    field :secret_ttl
    field :share_domain
    field :passphrase
    field :viewed
    field :received
    field :shared
    field :burned
    field :created
    field :updated
    field :recipients
    field :truncate # boolean

    # NOTE: this field is a nullop. It's only populated if a value was entered
    # into a hidden field which is something a regular person would not do.
    field :token

    @safe_dump_fields = [
      :key,
      :custid,
      :state,
      :secret_shortkey,
      :secret_ttl,
      :share_domain,
      :created,
      :updated,
      :recipients,

      { :shortkey => ->(m) { m.key.slice(0, 8) } },
      { :show_recipients => ->(m) { !m.recipients.to_s.empty? } },

      { :is_received => ->(m) { m.state?(:received) } },
      { :is_burned => ->(m) { m.state?(:burned) } },
      { :is_destroyed => ->(m) { m.state?(:received) || m.state?(:burned) } },

      # We use the hash syntax here since `:truncated?` is not a valid symbol.
      { :is_truncated => ->(m) { m.truncated? } }
    ]

    def init
      self.state ||= 'new'
    end

    def generate_id
      @key ||= Familia.generate_id.slice(0, 31)
      @key
    end

    def age
      @age ||= Time.now.utc.to_i-updated
      @age
    end

    def shortkey
      key.slice(0,6)
    end

    def anonymous?
      custid.to_s == 'anon'
    end

    def owner? cust
      !anonymous? && (cust.is_a?(OT::Customer) ? cust.custid : cust).to_s == custid.to_s
    end

    def deliver_by_email cust, locale, secret, eaddrs, template=nil, ticketno=nil
      template ||= OT::Email::SecretLink

      if eaddrs.nil? || eaddrs.empty?
        OT.info "[deliver-by-email] #{cust.obscure_email} #{secret.key} No addresses specified"
      end

      OT.info "[deliver-by-email2] #{cust.obscure_email} #{secret.key} (token/#{self.token})"
      eaddrs = [eaddrs].flatten.compact[0..9] # Max 10

      eaddrs_safe = eaddrs.collect { |e| OT::Utils.obscure_email(e) }
      eaddrs_safe_str = eaddrs_safe.join(', ')

      OT.info "[deliver-by-email3] #{cust.obscure_email} #{secret.key} (#{eaddrs_safe.size}) #{eaddrs_safe_str}"
      self.recipients! eaddrs_safe_str

      OT.ld "SECRET HAS MORE THAN ONE RECIPIENT #{eaddrs.size}" if eaddrs.size > 1
      eaddrs.each do |email_address|
        view = template.new cust, locale, secret, email_address
        view.ticketno = ticketno if (ticketno)
        view.emailer.from = cust.custid
        view.emailer.fromname = ''
        view.deliver_email self.token  # pass the token from spawn_pair through
        break # force just a single recipient
      end
    end

    def older_than? seconds
      age > seconds
    end

    def valid?
      exists?
    end

    # NOTE: We override the default fast writer (bang!) methods from familia
    # so that we can update two fields at once. To replicate the same behavior
    # we pass update_expiration: false to save so that changing this metdata
    # objects state doesn't affect its original expiration time.
    #
    # TODO: Replace with transaction (i.e. redis multi command)
    def viewed!
      # A guard to allow only a fresh, new secret to be viewed. Also ensures
      # that we don't support going from viewed back to something else.
      return unless state?(:new)
      self.state = 'viewed'
      self.viewed = Time.now.utc.to_i
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
    end

    def received!
      # A guard to allow only a fresh secret to be received. Also ensures
      # that we don't support going from received back to something else.
      return unless state?(:new) || state?(:viewed)
      self.state = 'received'
      self.received = Time.now.utc.to_i
      self.secret_key = ""
      save update_expiration: false
    end

    def burned!
      # See guard comment on `received!`
      return unless state?(:new) || state?(:viewed)
      self.state = 'burned'
      self.burned = Time.now.utc.to_i
      self.secret_key = ""
      save update_expiration: false
    end

    def state? guess
      state.to_s == guess.to_s
    end

    def truncated?
      truncate.to_s == 'true'
    end

    def load_secret
      OT::Secret.load secret_key
    end
  end
end
