# frozen_string_literal: true

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.load!

# Sessions don't have unique IDs by default
s1, s2 = OT::Session.new, OT::Session.new
s1.sessid == s2.sessid
#=> true

# Can set form fields
@sess = OT::Session.new
ret = @sess.set_form_fields :custid => 'tryouts', :planid => :testing
ret.class
#=> String

# Can get form fields, with indifferent access
ret = @sess.get_form_fields!
[ret.class, ret[:custid], ret['custid']]
#=> [Hash, 'tryouts', 'tryouts']
