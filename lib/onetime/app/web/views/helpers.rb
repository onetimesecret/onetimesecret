

module Onetime::Views::Helpers
  def add_shrimp
    '<input type="hidden" name="shrimp" value="%s" />' % [sess.add_shrimp]
  end
  def private_secret_uri m 
    '/private/%s' % m.key
  end
end