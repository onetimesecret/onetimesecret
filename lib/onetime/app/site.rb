
require 'onetime'  # must be required before
require 'onetime/app/site/base'


module Onetime
  class App
    include Base
  
    def index
      anonymous do
        view = Onetime::Views::Homepage.new req
        res.body = view.render
      end
    end
  
    #def not_found
    #  [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
    #end
  
    def create
      metadata, secret = nil, nil
      carefully do
        metadata, secret = Onetime::Secret.generate_pair :anon, [req.client_ipaddress, req.user_agent]
        metadata.passphrase = req.params[:passphrase] if !req.params[:passphrase].to_s.empty?
        secret.update_passphrase req.params[:passphrase] if !req.params[:passphrase].to_s.empty?
        if req.params[:kind] == 'share' && !req.params[:secret].to_s.strip.empty?
          secret.original_size = req.params[:secret].to_s.size
          secret.encrypt_value req.params[:secret].to_s.slice(0, 4999)
        elsif req.params[:kind] == 'generate'
          generated_value = Onetime::Utils.strand 12
          secret.original_size = generated_value.size
          secret.encrypt_value generated_value
        end
        secret.save
        metadata.save
        if metadata.valid? && secret.valid?
          uri = ['/private/', metadata.key].join
          res.redirect uri
        else
          res.redirect '/?errno=%s' % [Onetime.errno(:nosecret)]
        end
      end
    end
  
    def secret_uri
      carefully do
        deny_agents! 
        if Onetime::Secret.exists?(req.params[:key])
          secret = Onetime::Secret.load req.params[:key]
          if secret.state.to_s == "new"
            view = Onetime::Views::Shared.new req, res
            if secret.state? :viewed
              view[:show_secret] = false
            else
              if secret.has_passphrase?
                view[:has_passphrase] = true
                if secret.passphrase?(req.params[:passphrase])
                  view[:show_secret] = true
                  view[:secret_value] = secret.can_decrypt? ? secret.decrypted_value : secret.value
                  secret.viewed!
                elsif req.post? && req.params[:passphrase]
                  view[:show_secret] = false
                  view[:err] = "Double check that passphrase"
                end
              else
                if req.params[:continue] == 'true'
                  view[:show_secret] = true
                  view[:secret_value] = secret.can_decrypt? ? secret.decrypted_value : secret.value
                  secret.viewed!
                else
                  view[:show_secret] = false 
                end 
              end
            end
            res.body = view.render
          else
            raise OT::MissingSecret
          end
        else
          raise OT::MissingSecret
        end
      end
    end
 
    def private_uri
      carefully do
        deny_agents! 
        if Onetime::Metadata.exists?(req.params[:key])
          metadata = Onetime::Metadata.load req.params[:key]
          secret = metadata.load_secret
          unless secret.nil?
            # We temporarily store the raw passphrase when the private
            # secret is created so we can display it once. Here we 
            # update it with the encrypted one.
            secret.passphrase_temp = metadata.passphrase
            metadata.passphrase = secret.passphrase
          end
          view = Onetime::Views::Private.new req, res, metadata, secret
          unless metadata.state?(:viewed) || metadata.state?(:shared)
            metadata.viewed!
            view[:show_secret] = true
          end
          res.body = view.render
        else
          raise OT::MissingSecret
        end
      end
    end
  
    class Info
      include Base
      def privacy
        carefully do
          view = Onetime::Views::Info::Privacy.new req
          res.body = view.render
        end
      end
      def security
        carefully do
          view = Onetime::Views::Info::Security.new req
          res.body = view.render
        end
      end
    end
  end
end

module Onetime
  module Views
    class Homepage < Onetime::View
      def init *args
        self[:title] = "Share a secret"
        self[:monitored_link] = true
      end
    end
    module Info
      class Privacy < Onetime::View
        def init *args
          self[:title] = "Privacy Policy"
          self[:monitored_link] = true
        end
      end
       class Security < Onetime::View
        def init *args
          self[:title] = "Security Policy"
          self[:monitored_link] = true
        end
      end
    end
     class UnknownSecret < Onetime::View
      def init 
        self[:title] = "No such secret"
      end
    end
    class Shared < Onetime::View
      def init 
        self[:title] = "You received a secret"
        self[:body_class] = :generate
      end
      def display_lines
        ret = self[:secret_value].to_s.scan(/\n/).size + 2
        ret = ret > 20 ? 20 : ret
      end
      def one_liner
        self[:secret_value].to_s.scan(/\n/).size.zero?
      end
    end
    class Private < Onetime::View
      def init metadata, secret
        self[:title] = "You saved a secret"
        self[:body_class] = :generate
        self[:metadata_key] = metadata.key
        self[:been_shared] = metadata.state?(:shared)
        self[:shared_date] = natural_time(metadata.shared.to_i || 0)
        unless secret.nil?
          self[:secret_key] = secret.key
          self[:show_passphrase] = !secret.passphrase_temp.to_s.empty?
          self[:passphrase_temp] = secret.passphrase_temp
          self[:secret_value] = secret.can_decrypt? ? secret.decrypted_value : secret.value
        end
      end
      def share_uri
        [baseuri, :secret, self[:secret_key]].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:metadata_key]].join('/')
      end
      def display_lines
        ret = self[:secret_value].to_s.scan(/\n/).size + 2
        ret = ret > 20 ? 20 : ret
      end
      def one_liner
        self[:secret_value].to_s.scan(/\n/).size.zero?
      end
    end
    class Error < Onetime::View
      def init *args
        self[:title] = "Oh cripes!"
      end
    end
  end
  
end
