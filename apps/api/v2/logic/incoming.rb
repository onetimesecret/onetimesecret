# apps/api/v2/logic/incoming.rb

require_relative 'base'

module V2
  module Logic
    module Incoming
      class CreateIncoming < V2::Logic::Base
        attr_reader :passphrase, :secret_value, :ticketno, :metadata, :secret, :recipient, :ttl
        attr_accessor :token

        def process_params
          @ttl               = 7.days
          @secret_value      = params[:secret]
          @ticketno          = params[:ticketno].strip
          @passphrase        = OT.conf['incoming']['passphrase'].strip
          params[:recipient] = [OT.conf['incoming']['email']]
          r                  = /\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/
          @recipient         = params[:recipient].collect do |email_address|
            next if email_address.to_s.empty?

            email_address.scan(r).uniq.first
          end.compact.uniq
        end

        def raise_concerns
          regex = Regexp.new(OT.conf['incoming']['regex'] || '\A[a-zA-Z0-9]{1,32}\z')
          raise_form_error 'You did not provide any information to share' if secret_value.to_s.empty?
          return unless ticketno.to_s.empty? || !ticketno.match(regex)

          raise_form_error 'You must provide a valid ticket number'
        end

        def process
          @metadata, @secret       = V2::Secret.spawn_pair cust.custid, token
          unless passphrase.empty?
            secret.update_passphrase passphrase
            metadata.passphrase = secret.passphrase
          end
          secret.encrypt_value secret_value
          metadata.default_expiration             = ttl
          secret.default_expiration               = ttl
          metadata.secret_shortkey = secret.shortkey
          secret.save
          metadata.save
          if metadata.valid? && secret.valid?
            unless cust.anonymous?
              cust.add_metadata metadata
              cust.increment :secrets_created
            end
            V2::Customer.global.increment :secrets_created
            unless recipient.nil? || recipient.empty?
              metadata.deliver_by_email cust, locale, secret, recipient.first, Onetime::Mail::IncomingSupport, ticketno
            end
          else
            raise_form_error 'Could not store your secret'
          end
        end
      end
    end
  end
end
