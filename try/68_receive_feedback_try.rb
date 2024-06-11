# frozen_string_literal: true

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.load! :app

# Setup some variables for these tryouts
@now = DateTime.now
@model_class = OT::Feedback
@email_address = "tryouts+#{@now}@onetimesecret.com"
@sess = OT::Session.new
@cust = OT::Customer.new @email_address
@sess.event_clear! :send_feedback
@params = {
  msg: 'This is a test feedback'
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
#=> nil

## Sending feedback provides a UI message
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.process
@sess.info_message
#=> 'Message received. Send as much as you like!'

## Sending the same feedback from the same customer does not
## increment the count. A feature of using a redis set.
count_before = @model_class.recent.count
obj = OT::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.process
count_after = @model_class.recent.count
count_after - count_before
#=> 0

## Sending populates the Feedback model's sorted set key in redis
count_before = @model_class.recent.count
email_address = "tryouts2+#{@now}@onetimesecret.com"
sess = OT::Session.new
cust = OT::Customer.new email_address
obj = OT::Logic::ReceiveFeedback.new sess, cust, {msg: 'Some feedback'}
obj.process
count_after = @model_class.recent.count
count_after - count_before
#=> 1

## Sending feedback as an anonymous user raises a concern
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

## Feedback model exposes a recent method
recent_feedback = @model_class.recent
most_recent_pair = recent_feedback.to_a.last  # as an array [key, value]
most_recent_pair[0]
#=> "#{@params[:msg]} [#{@email_address}]"

## Feedback model exposes an all method
all_feedback = @model_class.recent
most_recent_pair = all_feedback.to_a.last
most_recent_pair[0]
#=> "#{@params[:msg]} [#{@email_address}]"

# Cleanup
puts 'clearing limiters'
@sess.event_clear! :send_feedback
