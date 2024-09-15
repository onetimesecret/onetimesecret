require_relative 'base'
require_relative '../../app_settings'


class Onetime::App
  class API
    include AppSettings
    include Onetime::App::API::Base

    @check_utf8 = true
    @check_uri_encoding = true

    # FlexibleHashAccess is a refinement for the Hash class that enables
    # the use of either strings or symbols interchangeably when
    # retrieving values from a hash.
    #
    # @see metadata_hsh method
    #
    using FlexibleHashAccess

    def status
      authorized(true) do
        sess.event_incr! :check_status
        json :status => :nominal, :locale => locale
      end
    end

    def share
      authorized(true) do
        req.params[:kind] = :share
        logic = OT::Logic::Secrets::CreateSecret.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        if req.get?
          res.redirect app_path(logic.redirect_uri)
        else
          secret = logic.secret
          json metadata_hsh(logic.metadata,
                              :secret_ttl => secret.realttl,
                              :passphrase_required => secret && secret.has_passphrase?)
        end
      end
    end

    def generate
      authorized(true) do
        req.params[:kind] = :generate
        logic = OT::Logic::Secrets::CreateSecret.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        if req.get?
          res.redirect app_path(logic.redirect_uri)
        else
          secret = logic.secret
          json metadata_hsh(logic.metadata,
                              :value => logic.secret_value,
                              :secret_ttl => secret.realttl,
                              :passphrase_required => secret && secret.has_passphrase?)
          logic.metadata.viewed!
        end
      end
    end

    def show_metadata
      authorized(true) do
        logic = OT::Logic::Secrets::ShowMetadata.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        secret = logic.metadata.load_secret
        if logic.show_secret
          secret_value = secret.can_decrypt? ? secret.decrypted_value : nil
          json metadata_hsh(logic.metadata,
                              :value => secret_value,
                              :secret_ttl => secret.realttl,
                              :passphrase_required => secret && secret.has_passphrase?)
        else
          json metadata_hsh(logic.metadata,
                              :secret_ttl => secret ? secret.realttl : nil,
                              :passphrase_required => secret && secret.has_passphrase?)
        end
        logic.metadata.viewed!
      end
    end

    def show_metadata_recent
      authorized(false) do
        logic = OT::Logic::Dashboard::ShowRecentMetadata.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        recent_metadata = logic.metadata.collect { |md|
          next if md.nil?
          hash = metadata_hsh(md)
          hash.delete :secret_key   # Don't call md.delete, that will delete from redis
          hash
        }.compact
        json recent_metadata
      end
    end

    def show_secret
      authorized(true) do
        req.params[:continue] = 'true'
        logic = OT::Logic::Secrets::ShowSecret.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        if logic.show_secret
          json :value => logic.secret_value, :secret_key => req.params[:key]

          # Immediately mark the secret as viewed, so that it
          # can't be shown again. If there's a network failure
          # that prevents the client from receiving the response,
          # we're not able to show it again. This is a feature
          # not a bug.
          logic.secret.received!
        else
          secret_not_found_response
        end
      end
    end

    # curl -X POST -u 'EMAIL:APIKEY' http://LOCALHOSTNAME:3000/api/v1/private/:key/burn
    def burn_secret
      authorized(true) do
        req.params[:continue] = 'true'
        logic = OT::Logic::Secrets::BurnSecret.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        if logic.greenlighted
          json :state           => metadata_hsh(logic.metadata),
               :secret_shortkey => logic.metadata.secret_shortkey
        else
          secret_not_found_response
        end
      end
    end

    def create
      authorized(true) do
        req.params[:kind] = :share
        logic = OT::Logic::Secrets::CreateSecret.new sess, cust, req.params, locale
        logic.token = ''.instance_of?(String).to_s  # lol a roundabout way to get to "true"
        logic.raise_concerns
        logic.process
        if req.get?
          res.redirect app_path(logic.redirect_uri)
        else
          secret = logic.secret
          json metadata_hsh(logic.metadata,
                              :secret_ttl => secret.realttl,
                              :passphrase_required => secret && secret.has_passphrase?)
        end
      end
    end

    # Transforms metadata into a structured hash with enhanced information.
    #
    # This method processes a metadata object and optional parameters to create
    # a comprehensive hash representation. It includes derived and calculated
    # values, providing a rich snapshot of the metadata and associated secret
    # state.
    #
    # @param md [Metadata] The metadata object to process
    # @param opts [Hash] Optional parameters to influence the output
    # @option opts [Integer, nil] :secret_ttl The actual TTL of the associated
    #   secret, if available
    #
    # @return [Hash] A structured hash containing metadata and derived
    #   information
    #
    # @note This method relies on the FlexibleHashAccess refinement for hash
    #   key access.
    #
    # @example Basic usage
    #   metadata = Metadata.new(key: 'abc123', custid: 'user@example.com')
    #   result = metadata_hsh(metadata)
    #   puts result[:custid] # => "user@example.com"
    #
    # @example With secret TTL provided
    #   result = metadata_hsh(metadata, secret_ttl: 3600)
    #   puts result[:secret_ttl] # => 3600
    #
    def metadata_hsh md, opts={}
      hsh = md.refresh.to_h

      # NOTE: This is a workaround for limitation in Familia where we can't add
      # fields that clash with reserved keywords like ttl, db, etc. For the v1
      # API, "ttl" is the requested value (i.e. the value of the ttl param when
      # the secret was created). Although this is getting the value from a
      # different field than the 0.16.x and earlier, it reads better (as in "the
      # secret has a ttl of 123") vs an ambiguous field called just ttl. It's
      # just confusing with the API response fields where `secret_ttl` is the
      # real value.
      #
      # Also note that the ttl used for metadata at creation time is secret_ttl*2
      # so that the creator has time to keep retreiving them metadata after the
      # secret itself has expired. Otherwise there'd be no record of whether the
      # secret was seen or not.
      metadata_ttl = (md.secret_ttl || 0).to_i

      # Show the secret's actual real ttl as of now if we have it.
      secret_realttl = opts[:secret_ttl] ? opts[:secret_ttl].to_i : nil

      # md.realttl is a redis command method. This makes a call to the redis server
      # to get the current value of the ttl for the metadata object. This is the
      # actual time left before the metadata object is deleted from the redis server.
      #
      # For the v1 API, this real value is what gets returned a "metadata_ttl". If
      # you don't find that confusing, take another look through the code.
      metadata_realttl = md.realttl.to_i

      recipient = [hsh['recipients']]
                  .flatten
                  .compact
                  .reject(&:empty?)
                  .uniq

      ret = {
        :custid => hsh['custid'],
        :metadata_key => hsh['key'],
        :secret_key => hsh['secret_key'],
        :ttl => metadata_ttl, # static value from redis hash field
        :metadata_ttl => metadata_realttl, # actual number of seconds left to live
        :secret_ttl => secret_realttl, # ditto, actual number
        :state => hsh['state'] || 'new',
        :updated => hsh['updated'].to_i,
        :created => hsh['created'].to_i,
        :received => hsh['received'].to_i,
        :recipient => recipient
      }
      if ret[:state] == 'received'
        ret.delete :secret_ttl
        ret.delete :secret_key
      else
        ret.delete :received
      end
      ret[:value] = opts[:value] if opts[:value]
      if !opts[:passphrase_required].nil?
        ret[:passphrase_required] = opts[:passphrase_required]
      end
      ret
    end
    private :metadata_hsh

  end
end

# Require after the above to avoid circular dependency
require_relative 'account'
require_relative 'domains'
