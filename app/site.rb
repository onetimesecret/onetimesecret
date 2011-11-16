
require 'onetime'  # must be required before
require 'site/base'


module Site
  extend Base
  extend self
  
  def index req, res
    carefully req, res do
      view = Site::Views::Homepage.new req
      res.body = view.render
    end
  end
  
  def create req, res
    psecret, ssecret = nil, nil
    carefully req, res do
      psecret, ssecret = Onetime::Secret.generate_pair [req.client_ipaddress, req.user_agent]
      psecret.passphrase = req.params[:passphrase] if !req.params[:passphrase].to_s.empty?
      ssecret.update_passphrase req.params[:passphrase] if !req.params[:passphrase].to_s.empty?
      if req.params[:kind] == 'share' && !req.params[:secret].to_s.strip.empty?
        ssecret.original_size = req.params[:secret].to_s.size
        ssecret.encrypt_value req.params[:secret].to_s.slice(0, 4999)
      elsif req.params[:kind] == 'generate'
        generated_value = Onetime::Utils.strand 12
        ssecret.original_size = generated_value.size
        ssecret.encrypt_value generated_value
      end
      psecret.save
      ssecret.save
      if psecret.valid? && ssecret.valid?
        uri = ['/private/', psecret.key].join
        res.redirect uri
      else
        res.redirect '/?errno=%s' % [Onetime.errno(:nosecret)]
      end
    end
  end
  
  def shared_uri req, res
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
      if Onetime::Secret.exists?(req.params[:key])
        psecret = Onetime::Secret.from_redis req.params[:key]
        ssecret = psecret.load_pair
        view = Site::Views::Private.new req, res, psecret, ssecret
        unless psecret.state?(:viewed) || psecret.state?(:shared)
          # We temporarily store the raw passphrase when the private
          # secret is created so we can display it once. Here we 
          # update it with the encrypted one.
          ssecret.passphrase_temp = psecret.passphrase
          psecret.passphrase = ssecret.passphrase
          psecret.viewed!
          view[:show_secret] = true
        end
        res.body = view.render
      else
        raise OT::MissingSecret
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
        [baseuri, :shared, self[:ssecret].key].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:psecret].key].join('/')
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
      def init psecret, ssecret
        self[:psecret], self[:ssecret] = psecret, ssecret
        self[:title] = "You saved a secret"
        self[:body_class] = :generate
      end
      def share_uri
        [baseuri, :shared, self[:ssecret].key].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:psecret].key].join('/')
      end
      def show_passphrase
        !self[:ssecret].passphrase_temp.to_s.empty?
      end
      def been_shared
        self[:psecret].state? :shared
      end
      def shared_date
        natural_time self[:psecret].shared || 0
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
