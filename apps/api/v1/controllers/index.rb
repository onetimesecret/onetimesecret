# apps/api/v1/controllers/index.rb

require_relative 'base'
require_relative 'settings'

module V1
  module Controllers
    class Index
      include ControllerBase
      include ControllerSettings

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

      def authcheck
        authorized(false) do
          sess.event_incr! :check_status
          json :status => :nominal, :locale => locale
        end
      end

      def share
        authorized(true) do
          logic = V1::Logic::Secrets::ConcealSecret.new sess, cust, {secret: req.params}, locale
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.metadata_hsh(logic.metadata,
                                :secret_ttl => secret.realttl,
                                :passphrase_required => secret && secret.has_passphrase?)
          end
        end
      end

      def generate
        authorized(true) do
          logic = V1::Logic::Secrets::GenerateSecret.new sess, cust, {secret: req.params}, locale
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.metadata_hsh(logic.metadata,
                                :value => logic.secret_value,
                                :secret_ttl => secret.realttl,
                                :passphrase_required => secret && secret.has_passphrase?)
            logic.metadata.viewed!
          end
        end
      end

      def show_metadata
        authorized(true) do
          logic = V1::Logic::Secrets::ShowMetadata.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          secret = logic.metadata.load_secret
          if logic.show_secret
            secret_value = secret.can_decrypt? ? secret.decrypted_value : nil
            json self.class.metadata_hsh(logic.metadata,
                                :value => secret_value,
                                :secret_ttl => secret.realttl,
                                :passphrase_required => secret && secret.has_passphrase?)
          else
            json self.class.metadata_hsh(logic.metadata,
                                :secret_ttl => secret ? secret.realttl : nil,
                                :passphrase_required => secret && secret.has_passphrase?)
          end
          logic.metadata.viewed!
        end
      end

      def show_metadata_recent
        authorized(false) do
          logic = V1::Logic::Dashboard::ShowRecentMetadata.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          recent_metadata = logic.metadata.collect { |md|
            next if md.nil?
            hash = self.class.metadata_hsh(md)
            hash.delete :secret_key   # Don't call md.delete, that will delete from redis
            hash
          }.compact
          json recent_metadata
        end
      end

      def show_secret
        authorized(true) do
          req.params[:continue] = 'true'
          logic = V1::Logic::Secrets::ShowSecret.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          if logic.show_secret
            json :value => logic.secret_value,
                :secret_key => req.params[:key],
                :share_domain => logic.share_domain
          else
            secret_not_found_response
          end
        end
      end

      # curl -X POST -u 'EMAIL:APITOKEN' http://LOCALHOSTNAME:3000/api/v1/private/:key/burn
      def burn_secret
        authorized(true) do
          req.params[:continue] = 'true'
          logic = V1::Logic::Secrets::BurnSecret.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          if logic.greenlighted
            json :state           => self.class.metadata_hsh(logic.metadata),
                :secret_shortkey => logic.metadata.secret_shortkey
          else
            secret_not_found_response
          end
        end
      end

      def create
        authorized(true) do
          req.params[:kind] = :share
          logic = V1::Logic::Secrets::ConcealSecret.new sess, cust, req.params, locale
          logic.token = ''.instance_of?(String).to_s  # lol a roundabout way to get to "true"
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.metadata_hsh(logic.metadata,
                                :secret_ttl => secret.realttl,
                                :passphrase_required => secret && secret.has_passphrase?)
          end
        end
      end

      require_relative 'class_methods'
      extend V1::Controllers::ClassMethods
    end
  end
end
