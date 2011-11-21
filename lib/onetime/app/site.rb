
require 'onetime'  # must be required before
require 'onetime/app/site/base'


module Site
  extend Base
  extend self
  
  def index req, res
    anonymous req, res do
      view = Site::Views::Homepage.new req
      res.body = view.render
    end
  end
  
  #def not_found
  #  [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
  #end
  
  def create req, res
    metadata, ssecret = nil, nil
    carefully req, res do
      metadata, ssecret = Onetime::Secret.generate_pair :anon, [req.client_ipaddress, req.user_agent]
      metadata.passphrase = req.params[:passphrase] if !req.params[:passphrase].to_s.empty?
      ssecret.update_passphrase req.params[:passphrase] if !req.params[:passphrase].to_s.empty?
      if req.params[:kind] == 'share' && !req.params[:secret].to_s.strip.empty?
        ssecret.original_size = req.params[:secret].to_s.size
        ssecret.encrypt_value req.params[:secret].to_s.slice(0, 4999)
      elsif req.params[:kind] == 'generate'
        generated_value = Onetime::Utils.strand 12
        ssecret.original_size = generated_value.size
        ssecret.encrypt_value generated_value
      end
      metadata.save
      ssecret.save
      if metadata.valid? && ssecret.valid?
        uri = ['/private/', metadata.key].join
        res.redirect uri
      else
        res.redirect '/?errno=%s' % [Onetime.errno(:nosecret)]
      end
    end
  end
  
  def secret_uri req, res
    carefully req, res do
      deny_agents! req, res
      if Onetime::Secret.exists?(req.params[:key])
        ssecret = Onetime::Secret.from_redis req.params[:key]
        if ssecret.state.to_s == "new"
          view = Site::Views::Shared.new req, res, ssecret
          if ssecret.state? :viewed
            view[:show_secret] = false
          else
            if ssecret.has_passphrase?
              view[:has_passphrase] = true
              if ssecret.passphrase?(req.params[:passphrase])
                view[:show_secret] = true
                ssecret.viewed!
              elsif req.post? && req.params[:passphrase]
                view[:show_secret] = false
                view[:err] = "Double check that passphrase"
              end
            else
              if req.params[:continue] == 'true'
                view[:show_secret] = true 
                ssecret.viewed!
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
 
  def private_uri req, res
    carefully req, res do
      deny_agents! req, res
      if Onetime::Metadata.exists?(req.params[:key])
        metadata = Onetime::Metadata.from_redis req.params[:key]
        ssecret = metadata.load_secret
        view = Site::Views::Private.new req, res, metadata, ssecret
        unless metadata.state?(:viewed) || metadata.state?(:shared)
          # We temporarily store the raw passphrase when the private
          # secret is created so we can display it once. Here we 
          # update it with the encrypted one.
          ssecret.passphrase_temp = metadata.passphrase
          metadata.passphrase = ssecret.passphrase
          metadata.viewed!
          view[:show_secret] = true
        end
        res.body = view.render
      else
        raise OT::MissingSecret
      end
    end
  end
  
  module Info
    extend Base
    extend self
    def privacy req, res
      carefully req, res do
        view = Site::Views::Info::Privacy.new req
        res.body = view.render
      end
    end
    def security req, res
      carefully req, res do
        view = Site::Views::Info::Security.new req
        res.body = view.render
      end
    end
  end
  
  module Views
    class Homepage < Site::View
      def init *args
        self[:title] = "Share a secret"
        self[:monitored_link] = true
      end
    end
    module Info
      class Privacy < Site::View
        def init *args
          self[:title] = "Privacy Policy"
          self[:monitored_link] = true
        end
      end
       class Security < Site::View
        def init *args
          self[:title] = "Security Policy"
          self[:monitored_link] = true
        end
      end
    end
     class UnknownSecret < Site::View
      def init 
        self[:title] = "No such secret"
      end
    end
    class Shared < Site::View
      def init ssecret
        self[:ssecret] = ssecret
        self[:title] = "You received a secret"
        self[:body_class] = :generate
      end
      def share_uri
        [baseuri, :secret, self[:ssecret].key].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:metadata].key].join('/')
      end
      def display_lines
        ret = self[:ssecret].decrypted_value.to_s.scan(/\n/).size + 2
        ret = ret > 20 ? 20 : ret
      end
      def one_liner
        self[:ssecret].decrypted_value.to_s.scan(/\n/).size.zero?
      end
    end
    class Private < Site::View
      def init metadata, ssecret
        self[:metadata], self[:ssecret] = metadata, ssecret
        self[:title] = "You saved a secret"
        self[:body_class] = :generate
      end
      def share_uri
        [baseuri, :secret, self[:ssecret].key].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:metadata].key].join('/')
      end
      def show_passphrase
        !self[:ssecret].passphrase_temp.to_s.empty?
      end
      def been_shared
        self[:metadata].state? :shared
      end
      def shared_date
        natural_time self[:metadata].shared || 0
      end
      def display_lines
        ret = secret_value.to_s.scan(/\n/).size + 2
        ret = ret > 20 ? 20 : ret
      end
      def one_liner
        secret_value.to_s.scan(/\n/).size.zero?
      end
      def secret_value
        self[:ssecret].can_decrypt? ? self[:ssecret].decrypted_value : self[:ssecret].value
      end
    end
    class Error < Site::View
      def init *args
        self[:title] = "Oh cripes!"
      end
    end
  end
  
end
