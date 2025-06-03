# tests/unit/ruby/try/68_receive_feedback_try.rb

# These tryouts test the feedback receiving functionality in the Onetime application.
# They cover various aspects of handling user feedback, including:
#
# 1. Creating and processing feedback instances
# 2. Validating feedback input
# 3. Handling anonymous feedback attempts
# 4. Storing and retrieving recent feedback
# 5. Preventing duplicate feedback submissions
#
# These tests aim to ensure that user feedback is properly received, validated, and stored,
# which is important for gathering user input and improving the application.
#
# The tryouts use the V2::Logic::ReceiveFeedback class to simulate different feedback submission
# scenarios, allowing for targeted testing of this feature without affecting the actual feedback database.

require_relative './test_models'
require 'v2/logic/feedback'
require 'v2/controllers/challenges'

# Load the app
OT.boot! :test, true
V1::RateLimit.register_events OT.conf[:limits]

# Setup some variables for these tryouts
@now = DateTime.now
@model_class = V2::Feedback
@email_address = "tryouts+#{@now}@onetimesecret.com"
@sess = V1::Session.new '255.255.255.255', 'anon'
@cust = V1::Customer.new @email_address
@sess.event_clear! :send_feedback
@params = {
  msg: 'This is a test feedback'
}
@locale = 'en'

# TRYOUTS

## Can create ReceiveFeedback instance
obj = V2::Logic::ReceiveFeedback.new @sess, @cust
obj.class
#=> V2::Logic::ReceiveFeedback

## Can create ReceiveFeedback instance w/ params
obj = V2::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.params.keys
#=> [:msg]

## Can create ReceiveFeedback instance w/ params and locale
obj = V2::Logic::ReceiveFeedback.new @sess, @cust, @params, @locale
obj.locale
#=> 'en'

## Params are processed
obj = V2::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.msg
#=> 'This is a test feedback'

## Concerns can be raised when no message is given
obj = V2::Logic::ReceiveFeedback.new @sess, @cust, {}
begin
  obj.raise_concerns
rescue Onetime::FormError => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "You can be more original than that!"]

## Concerns are not raised when a message is given
obj = V2::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.raise_concerns
#=> nil

## Sending feedback provides a UI message
obj = V2::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.process
[@sess.get_info_messages, obj.success_data] # Since 0.18.3
#=> [[], {:success=>true, :record=>{}, :details=>{:message=>"Message received. Send as much as you like!"}}]

## Sending the same feedback from the same customer does not
## increment the count. A feature of using a redis set.
count_before = @model_class.recent.count
obj = V2::Logic::ReceiveFeedback.new @sess, @cust, @params
obj.process
count_after = @model_class.recent.count
count_after - count_before
#=> 0

## Sending populates the Feedback model's sorted set key in redis
count_before = @model_class.recent.count
email_address = "tryouts2+#{@now}@onetimesecret.com"
sess = V2::Session.new '255.255.255.255', 'anon'
cust = V1::Customer.new email_address
obj = V2::Logic::ReceiveFeedback.new sess, cust, { msg: 'Some feedback' }
obj.process
count_after = @model_class.recent.count
count_after - count_before
#=> 1

## Sending feedback as an anonymous user without verification raises a concern
cust = V1::Customer.anonymous
sess = V2::Session.new 'id123', cust, "tryouts"
sess.event_clear! :send_feedback
params = { msg: 'This is a test feedback' }
obj = V2::Logic::ReceiveFeedback.new sess, cust, params
begin
  obj.raise_concerns
rescue Onetime::FormError => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "Cannot skip authenticity check"]

## Sending feedback as an anonymous user with a bad verification raises a concern
cust = V1::Customer.anonymous
sess = V2::Session.new 'id123', cust, "tryouts"
sess.event_clear! :send_feedback
params = { msg: 'This is a test feedback', authenticity_payload: "123" }
obj = V2::Logic::ReceiveFeedback.new sess, cust, params
begin
  obj.raise_concerns
rescue Onetime::FormError => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "You need to be carbon-based to do that"]

## Sending feedback as an anonymous user with a verification works
cust = V1::Customer.anonymous
sess = V2::Session.new 'id123', cust, "tryouts"
sess.event_clear! :send_feedback
challenge = V2::Controllers::Challenges.generate_authenticity_challenge(5000) # very low
solution = V2::Controllers::Challenges.solve_authenticity_challenge(challenge.challenge, challenge.salt, challenge.algorithm, challenge.maxnumber, 0)
payload = V2::Controllers::Challenges._authenticity_challenge_payload(challenge, solution.number)
payload_encoded = Base64.encode64(payload.to_json)
p [:challenge, challenge]
p [:solution, solution]
p [:payload_encoded, payload_encoded]
params = { msg: 'This is a test feedback', authenticity_payload: payload_encoded }
obj = V2::Logic::ReceiveFeedback.new sess, cust, params
obj.process_params
obj.raise_concerns
obj.verified
#=> true

## Feedback model exposes a recent method
recent_feedback = @model_class.recent
most_recent_pair = recent_feedback.to_a.last # as an array [key, value]
most_recent_pair[0]
#=> "#{@params[:msg]} [#{@email_address}] [TZ: ] [v]"

## Feedback model exposes an all method
all_feedback = @model_class.recent
most_recent_pair = all_feedback.to_a.last
most_recent_pair[0]
#=> "#{@params[:msg]} [#{@email_address}] [TZ: ] [v]"

# Cleanup
puts 'clearing limiters'
@sess.event_clear! :send_feedback
