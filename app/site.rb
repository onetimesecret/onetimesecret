
require 'site/base'
require 'ots'
require 'gibbler'

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
        res.redirect '/generate'
      else
        view = Site::Views::Generate.new
        view[:secret] = OTS::Utils.strand
        view[:admin_uri] = ['private', rand.gibbler.base(36)].join('/')
        view[:share_uri] = [rand.gibbler.base(36)].join('/')
        res.body = view.render
      end
    end
  end
  
  def admin_uri req, res
    res.header['Content-Type'] = 'text/plain'
    res.body = req.params.inspect
  end
  
  module Views
    class Homepage < Site::View
      def init *args
        self[:title] = "Share a secret"
        self[:subtitle] = "One Time"
      end
    end
    class Generate < Site::View
      def init *args
        self[:title] = "Generate a secret"
        self[:body_class] = :generate
      end
    end
    class Error < Site::View
      def init *args
        self[:title] = "Oh cripes!"
      end
    end
  end
  
end