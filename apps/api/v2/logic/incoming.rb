# apps/api/v2/logic/incoming.rb

require_relative 'base'

module V2
  module Logic
    module Incoming
      class CreateIncoming < V2::Logic::Base
        attr_reader :passphrase, :secret_value, :ticketno
        attr_reader :metadata, :secret, :recipient, :ttl
        attr_accessor :token

        def process_params
          @ttl = 7.days
          @secret_value = params[:secret]
          @ticketno = params[:ticketno].strip
          @passphrase = OT.conf[:incoming][:passphrase].strip
          params[:recipient] = [OT.conf[:incoming][:email]]
          r = Regexp.new(/\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/)
          @recipient = params[:recipient].collect { |email_address|
            next if email_address.to_s.empty?

            email_address.scan(r).uniq.first
          }.compact.uniq
        end

        def raise_concerns
          limit_action :create_secret
          limit_action :email_recipient unless recipient.empty?
          regex = Regexp.new(OT.conf[:incoming][:regex] || '\A[a-zA-Z0-9]{1,32}\z')
          if secret_value.to_s.empty?
            raise_form_error 'You did not provide any information to share'
          end
          if ticketno.to_s.empty? || !ticketno.match(regex)
            raise_form_error 'You must provide a valid ticket number'
          end
        end

        def process
          @metadata, @secret = V2::Secret.spawn_pair cust.custid, token
          if !passphrase.empty?
            secret.update_passphrase passphrase
            metadata.passphrase = secret.passphrase
          end
          secret.encrypt_value secret_value, size: plan.options[:size]
          metadata.ttl, secret.ttl = ttl, ttl
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
            V2::Logic.stathat_count('Secrets', 1)
          else
            raise_form_error 'Could not store your secret'
          end
        end
      end
    end
  end
end
