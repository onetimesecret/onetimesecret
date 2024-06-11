# frozen_string_literal: true

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.load! :app

# Setup some variables for these tryouts
@now = DateTime.now
@model_class = OT::Feedback
@sess = OT::Session.new
@cust = OT::Customer.new "tryouts+#{@now}@onetimesecret.com"
@sess.event_clear! :send_feedback
@params = {
  msg: "This is a test feedback"
}
@locale = 'en'
puts 'before2'

# TRYOUTS

## Can create ReceiveFeedback instance
obj = OT::Logic::ReceiveFeedback.new @sess, @cust
obj.class
#=> Onetime::Logic::ReceiveFeedback

## Can create ReceiveFeedback instance w/ params
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.params.keys
#=> [:msg]

## Can create ReceiveFeedback instance w/ params and locale
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, @params, @locale
obj.locale
#=> 'en'

## Params are processed
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.msg
#=> 'This is a test feedback'

## Concerns can be raised when no message is given
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, {}
begin
  obj.raise_concerns
rescue Onetime::FormError => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "You can be more original than that!"]

## Concerns are not raised when a message is given
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.raise_concerns
#=> [Onetime::FormError, "You can be more original than that!"]

## Sending feedback provides a UI message
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.process
@sess.info_message
#=> 'Message received. Send as much as you like!'

## Sending populates the Feedback model's sorted set key in redis
count_before = @model_class.recent.count
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, @params
count_after = @model_class.recent.count
obj.process
[count_after, count_before]
#=> 1

## Sending feedback provides a UI message
cust = OT::Customer.anonymous
sess = OT::Session.new 'id123', 'tryouts', cust
params = {msg: 'This is a test feedback'}
obj = OT::Logic::ReceiveFeedback.new sess, cust, params
sess.event_clear! :send_feedback
begin
  obj.raise_concerns
rescue Onetime::FormError => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "You need an account to do that"]


# Cleanup
puts 'clearing limiters'
@sess.event_clear! :send_feedback
