# apps/api/v2/controllers/class_methods.rb

module V2

  # FlexibleHashAccess is a refinement for the Hash class that enables
  # the use of either strings or symbols interchangeably when
  # retrieving values from a hash.
  #
  # @see metadata_hsh method
  #
  using FlexibleHashAccess

  module Controllers
    module ClassMethods
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
      #   result = API.metadata_hsh(metadata)
      #   puts result[:custid] # => "user@example.com"
      #
      # @example With secret TTL provided
      #   result = API.metadata_hsh(metadata, secret_ttl: 3600)
      #   puts result[:secret_ttl] # => 3600
      #
      def metadata_hsh md, opts={}

        # The to_h method comes from Familia::Horreum which is concerned with
        # preparing values for storage in redis. As a result, the hash returned
        # has had its values passed through `to_redis` where everything becomes
        # a string. e.g. nil becomes ''. We not only allow but encourage this
        # behaviour since the values will become strings in Redis anyway so
        # better to be explicit about it.
        hsh = md.to_h

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
        metadata_ttl = md.secret_ttl&.to_i

        # Show the secret's actual real ttl as of now if we have it.
        secret_realttl = opts[:secret_ttl]&.to_i

        # md.realttl is a redis command method. This makes a call to the redis server
        # to get the current value of the ttl for the metadata object. This is the
        # actual time left before the metadata object is deleted from the redis server.
        #
        # For the v1 API, this real value is what gets returned a "metadata_ttl". If
        # you don't find that confusing, take another look through the code.
        metadata_realttl = md.realttl&.to_i

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
          :updated => hsh['updated']&.to_i,
          :created => hsh['created']&.to_i,
          :received => hsh['received']&.to_i, # empty fields become 0
          :recipient => recipient,
          :share_domain => hsh['share_domain'],
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
    end
  end
end
