require 'site/base'

module Site
  extend Base
  extend self

  def index req, res
    carefully req, res do
      view = Site::Views::Homepage.new
      res.body = view.render
    end
  end
  
  module Views
    class Homepage < Site::View
      def init *args
        self[:title] = "Share a secret"
        self[:subtitle] = "One Time"
      end
    end
    class Error < Site::View
      def init *args
        self[:title] = "Oh cripes!"
      end
    end
  end
  
end