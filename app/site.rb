
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
  
  def generate req, res
    carefully req, res do
      if req.post?
        @psecret, @ssecret = Onetime::Secret.generate_pair [req.client_ipaddress, req.user_agent]
        @ssecret.value = Onetime::Utils.strand 12
        @psecret.save
        @ssecret.save
        uri = ['/private/', @psecret.key].join
        res.redirect uri
      else
        view = Site::Views::Generate.new
        res.body = view.render
      end
    end
  end
  
  def share req, res
    carefully req, res do
      if req.post?
        @psecret, @ssecret = Onetime::Secret.generate_pair [req.client_ipaddress, req.user_agent]
        @ssecret.value = req.params[:secret].to_s.slice(0, 500)
        @psecret.save
        @ssecret.save
        uri = ['/private/', @psecret.key].join
        res.redirect uri
      else
        view = Site::Views::Share.new
        res.body = view.render
      end
    end
  end
  
  def shared_uri req, res
    carefully req, res do
      deny_agents! req, res
      view = Site::Views::Shared.new
      if Onetime::Secret.exists?(req.params[:key])
        ssecret = Onetime::Secret.from_redis req.params[:key]
        if ssecret.state.to_s == "new"
          view[:ssecret] = ssecret
          view[:show_secret] = ssecret.state.to_s == 'new'
          if ssecret.state.to_s == 'new'
            ssecret.state = 'viewed'
            ssecret.save
          end
          res.body = view.render
        else
          res.redirect '/'
        end
      else
        res.redirect '/'
      end
    end
  end
  
  def private_uri req, res
    carefully req, res do
      deny_agents! req, res
      view = Site::Views::Private.new
      if Onetime::Secret.exists?(req.params[:key])
        psecret = Onetime::Secret.from_redis req.params[:key]
        ssecret = psecret.load_pair
        view[:psecret], view[:ssecret] = psecret, ssecret
        view[:show_secret] = psecret.state.to_s == 'new'
        if psecret.state.to_s == 'new'
          psecret.state = 'viewed'
          psecret.save
        end
        res.body = view.render
      else
        res.redirect '/'
      end
    end
  end
  
  module Views
    class Homepage < Site::View
      def init *args
        self[:title] = "Share a secret"
      end
    end
    class Generate < Site::View
      def init *args
        self[:title] = "Generate a secret"
        self[:body_class] = :generate
      end
    end
    class Share < Site::View
      def init *args
        self[:title] = "Share a secret"
        self[:body_class] = :share
      end
    end
    class Shared < Site::View
      def init *args
        self[:title] = "Shhh, it's a secret"
        self[:body_class] = :generate
      end
      def share_uri
        [baseuri, :shared, self[:ssecret].key].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:psecret].key].join('/')
      end
    end
    class Private < Site::View
      def init *args
        self[:title] = "Shhh, it's a secret"
        self[:body_class] = :generate
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