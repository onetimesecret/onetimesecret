# apps/api/v1/controllers/index.rb
#
# frozen_string_literal: true

require 'v1/refinements'

require_relative 'base'
require_relative 'settings'

module V1
  module Controllers
    # V1 Controller Endpoints [#2615]
    #
    # All endpoints that return receipt/secret data use receipt_hsh (via
    # self.class.receipt_hsh) to map internal v0.24 vocabulary back to
    # v0.23.x field names. Each call passes :custid => cust.email so the
    # response contains the email address, not the internal UUID.
    #
    # The burn response uses :secret_shortkey (v0.23.x name) for the
    # truncated secret identifier, even though the model method is
    # secret_shortid (v0.24 name).
    #
    # GET /private/:key was supported in v0.23.x but v0.24 only routes
    # POST for receipt lookup. This is a known behavioral change.
    #
    class Index
      include ControllerBase
      include ControllerSettings

      @check_utf8 = true
      @check_uri_encoding = true

      # FlexibleHashAccess is a refinement for the Hash class that enables
      # the use of either strings or symbols interchangeably when
      # retrieving values from a hash.
      #
      # @see receipt_hsh method
      #
      using FlexibleHashAccess

      def status
        authorized(true) do
          json :status => :nominal, :locale => locale
        end
      end

      def authcheck
        authorized(false) do
          json :status => :nominal, :locale => locale
        end
      end

      def share
        authorized(true) do
          logic = V1::Logic::Secrets::ConcealSecret.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect req.app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust.email,
                                :secret_ttl => secret.current_expiration,
                                :passphrase_required => secret && secret.has_passphrase?)
          end
        end
      end

      def generate
        authorized(true) do
          logic = V1::Logic::Secrets::GenerateSecret.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect req.app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust.email,
                                :value => logic.secret_value,
                                :secret_ttl => secret.current_expiration,
                                :passphrase_required => secret && secret.has_passphrase?)
            logic.receipt.previewed!
          end
        end
      end

      def show_receipt
        authorized(true) do
          logic = V1::Logic::Secrets::ShowReceipt.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          # Reuse data already loaded/decrypted in logic.process rather than
          # re-loading the secret from Redis and re-decrypting (which can fail).
          if logic.show_secret
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust.email,
                                :value => logic.secret_value,
                                :secret_ttl => logic.secret_realttl,
                                :passphrase_required => logic.has_passphrase)
          else
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust.email,
                                :secret_ttl => logic.secret_realttl,
                                :passphrase_required => logic.has_passphrase)
          end
          logic.receipt.previewed!
        end
      end

      def show_receipt_recent
        authorized(false) do
          logic = V1::Logic::Secrets::ShowReceiptList.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          recent_receipts = logic.receipts.collect { |md|
            next if md.nil?
            hash = self.class.receipt_hsh(md, :custid => cust.email)
            hash.delete 'secret_key'  # Don't call md.delete, that will delete from the db
            hash
          }.compact
          json recent_receipts
        end
      end

      def show_secret
        authorized(true) do
          req.params['continue'] = 'true'
          logic = V1::Logic::Secrets::ShowSecret.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          if logic.show_secret
            json :value => logic.secret_value,
                :secret_key => req.params['key'],
                :share_domain => logic.share_domain
          else
            secret_not_found_response
          end
        end
      end

      # curl -X POST -u 'EMAIL:APITOKEN' http://LOCALHOSTNAME:3000/api/v1/receipt/:key/burn
      def burn_secret
        authorized(true) do
          req.params['continue'] = 'true'
          logic = V1::Logic::Secrets::BurnSecret.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          if logic.greenlighted
            json :state           => self.class.receipt_hsh(logic.receipt, :custid => cust.email),
                :secret_shortkey => logic.receipt.secret_shortid
          else
            secret_not_found_response
          end
        end
      end

      def create
        authorized(true) do
          logic = V1::Logic::Secrets::ConcealSecret.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect req.app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust.email,
                                :secret_ttl => secret.current_expiration,
                                :passphrase_required => secret && secret.has_passphrase?)
          end
        end
      end

      require_relative 'class_methods'
      extend V1::Controllers::ClassMethods
    end
  end
end
