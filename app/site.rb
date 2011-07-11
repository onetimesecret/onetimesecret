
require 'site/base'
require 'onetime'

module Site
  extend Base
  extend self
  
  def index req, res
    carefully req, res do
      view = Site::Views::Homepage.new
      res.body = view.render
    end
  end
  
  def create req, res
    carefully req, res do
      if req.params[:kind] == 'generate'
        @psecret, @ssecret = Onetime::Secret.generate_pair [req.client_ipaddress, req.user_agent]
        @ssecret.value = Onetime::Utils.strand 12
      elsif req.params[:kind] == 'share'
        @psecret, @ssecret = Onetime::Secret.generate_pair [req.client_ipaddress, req.user_agent]
        @ssecret.value = req.params[:secret].to_s.slice(0, 500)
      end
      if @psecret && @ssecret
        @psecret.save
        @ssecret.save
        uri = ['/private/', @psecret.key].join
        res.redirect uri
      else
        res.redirect '/'
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
          view[:show_secret] = ssecret.state.to_s == 'new'
          if ssecret.state.to_s == 'new'
            ssecret.state = 'viewed'
            ssecret.save
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
        view[:show_secret] = psecret.state.to_s == 'new'
        if psecret.state.to_s == 'new'
          psecret.state = 'viewed'
          psecret.save
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
        self[:title] = "Shhh, it's a secret"
        self[:body_class] = :generate
        self[:show_secret] = false
      end
      def share_uri
        [baseuri, :shared, self[:ssecret].key].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:psecret].key].join('/')
      end
    end
    class Private < Site::View
      def init psecret, ssecret
        self[:psecret], self[:ssecret] = psecret, ssecret
        self[:title] = "Shhh, it's a secret"
        self[:body_class] = :generate
        self[:show_secret] = false
      end
      def share_uri
        [baseuri, :shared, self[:ssecret].key].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:psecret].key].join('/')
      end
      def been_shared
        self[:ssecret].state.to_s == "viewed"
      end
      def shared_date
        natural_time self[:ssecret].updated || 0
      end
    end
    class Error < Site::View
      def init *args
        self[:title] = "Oh cripes!"
      end
    end
  end
  
end