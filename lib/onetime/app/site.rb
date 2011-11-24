
require 'onetime'  # must be required before
require 'onetime/app/site/base'


module Onetime
  class App
    include Base
  
    def index
      anonymous do
        view = Onetime::Views::Homepage.new req
        sess.event_incr! :homepage
        res.body = view.render
      end
    end
  
    #def not_found
    #  [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
    #end
  
    def create
      anonymous do
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect logic.redirect_uri
      end
    end
  
    def secret_uri
      anonymous do
        deny_agents! 
        logic = OT::Logic::ShowSecret.new sess, cust, req.params
        view = Onetime::Views::Shared.new req, res
        logic.raise_concerns
        logic.process
        view[:has_passphrase] = logic.secret.has_passphrase?
        if logic.show_secret
          view[:show_secret] = true
          view[:secret_value] = logic.secret_value
        elsif req.post?
          view[:err] = "Double check that passphrase"
        end
        res.body = view.render
      end
    end
 
    def private_uri
      carefully do
        deny_agents! 
        logic = OT::Logic::ShowMetadata.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::Views::Private.new req, res, logic.metadata, logic.secret
        if logic.show_secret
          view[:show_secret] = true
        end
        res.body = view.render
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
