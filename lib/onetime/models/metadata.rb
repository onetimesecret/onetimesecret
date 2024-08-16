
module Onetime
  class Metadata < Familia::Horreum
    include Gibbler::Complex

    db 7
    ttl 14.days
    prefix :metadata

    identifier :generate_id

    field :custid
    field :state
    field :key
    field :secret_key
    field :passphrase
    field :viewed
    field :shared
    field :created
    field :updated

    # NOTE: this field is a nullop. It's only populated if a value was entered
    # into a hidden field which is something a regular person would not do.
    field :token

    def init
      self.state ||= 'new'
    end

    def generate_id
      @key ||= Familia.generate_id.slice(0, 31)
      @key
    end

    # Temporary until familia v1.0.0.pre-rc2
    def hgetall(suffix = nil)
      redis.hgetall rediskey(suffix)
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

    def deliver_by_email cust, locale, secret, eaddrs, template=OT::Email::SecretLink, ticketno=null
      if eaddrs.nil? || eaddrs.empty?
        OT.info "[deliver-by-email] #{cust.obscure_email} #{secret.key} No addresses specified"
      end
      OT.info "[deliver-by-email] #{cust.obscure_email} #{secret.key} (token/#{self.token})"
      eaddrs = [eaddrs].flatten.compact[0..9] # Max 10
      eaddrs_safe = eaddrs.collect { |e| OT::Utils.obscure_email(e) }
      self.recipients = eaddrs_safe.join(', ')
      OT.ld "SECRET HAS MORE THAN ONE RECIPIENT #{eaddrs.size}" if eaddrs.size > 1
      eaddrs.each do |email_address|
        view = template.new cust, locale, secret, email_address
        view.ticketno = ticketno if (ticketno)
        view.emailer.from = cust.custid
        view.emailer.fromname = ''
        ret = view.deliver_email self.token  # pass the token from spawn_pair through
        break # force just a single recipient
      end
    end

    def older_than? seconds
      age > seconds
    end

    def valid?
      exists?
    end

    def viewed!
      # A guard to allow only a fresh, new secret to be viewed. Also ensures
      # that we don't support going from viewed back to something else.
      return unless state?(:new)
      self.state = 'viewed'
      self.viewed = Time.now.utc.to_i
      # TODO: Confirm that the nuance bewteen being "viewed" vs "received"
      # or "burned" is that the secret link page has been requested (via GET)
      # but the "View Secret" button hasn't been clicked yet (i.e. we haven't
      # yet received the POST request that actually reveals the contents
      # of the secret). It's a subtle but important distinction bc it
      # communicates an amount of activity around the secret. The terminology
      # can be improved though and we'll also want to achieve parity with the
      # API by allowing a GET (or OPTIONS) for the secret as a check that it
      # is still valid -- that should set the state to viewed as well.
      save
    end

    def received!
      # A guard to allow only a fresh secret to be received. Also ensures
      # that we don't support going from received back to something else.
      return unless state?(:new) || state?(:viewed)
      self.state = 'received'
      self.received = Time.now.utc.to_i
      self.secret_key = ""
      save
    end

    def burned!
      # See guard comment on `received!`
      return unless state?(:new) || state?(:viewed)
      self.state = 'burned'
      self.burned = Time.now.utc.to_i
      self.secret_key = ""
      save
    end

    def state? guess
      state.to_s == guess.to_s
    end

    def load_secret
      OT::Secret.load secret_key
    end

    class << self
      def exists? objid
        obj = new key: objid
        obj.exists?
      end

      def load objid
        obj = new key: objid
        obj.exists? ? obj : nil
      end

      def create custid
        obj = new custid: custid
        # force the storing of the fields to redis
        obj.save
        obj
      end
    end
  end
end
