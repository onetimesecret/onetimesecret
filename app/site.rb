require 'site/base'

module Site
  extend Base
  extend self

  def index req, res
    carefully req, res do
      view = Site::Views::Homepage.new
      res.body = [view.render]
    end
  end
  
  module Views
    class Homepage < Site::View
    end
    class Error < Site::View
      def init *args
        @title = "Oh cripes!"
      end
    end
  end
  
end