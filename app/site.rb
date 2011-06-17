

module Site
  extend self
  
  def index req, res
    res.body = "1"
  rescue => ex
    puts ex.message, ex.backtrace
  end
  
end