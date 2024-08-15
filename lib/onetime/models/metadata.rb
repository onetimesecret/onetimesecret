
module Onetime
  class Metadata < Familia::Horreum
    include Gibbler::Complex

    db 7
    ttl 14.days

    identifier :custid

    field :custid
    field :token
    field :state
    field :key
    field :secret_key
    field :passphrase
    field :viewed
    field :shared
    field :created
    field :updated

    def init
      self.state ||= :new
      @key = gibbler.base(36)
    end

    def key= objid
      @key = objid
      @name = name
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
      # Make sure we don't go from :shared to :viewed
      return unless state?(:new)
      self.state = :viewed
      self.viewed = Time.now.utc.to_i
      save
    end
    def received!
      # Make sure we don't go from :shared to :viewed
      return unless state?(:new) || state?(:viewed)
      self.state = :received
      self.received = Time.now.utc.to_i
      self.secret_key = ""
      save
    end
    def burned!
      # Make sure we don't go from :shared to :viewed
      return unless state?(:new) || state?(:viewed)
      @state = :burned
      self.state = :burned
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
        obj = new
        obj.key = objid
        obj.exists?
      end
      def load objid
        obj = new
        obj.key = objid
        obj.exists? ? obj : nil
      end
      def create custid, entropy=[]
        obj = new custid
        # force the storing of the fields to redis
        obj.save
        obj
      end
    end
  end
end
