# tests/unit/ruby/try/19_safe_dump_try.rb

# These tryouts test the safe dumping functionality.

require_relative './test_models'

# Use the default config file for tests
OT.boot! :test, true

@email = 'tryouts-19@onetimesecret.com'

## By default there are no safe dump fields
Familia::Features::SafeDump.safe_dump_fields
#=> []

## Implementing models like Customer can define safe dump fields
Customer.safe_dump_fields
#=> [:identifier, :custid, :email, :role, :verified, :last_login, :locale, :updated, :created, :stripe_customer_id, :stripe_subscription_id, :stripe_checkout_email, :plan, :secrets_created, :secrets_burned, :secrets_shared, :emails_sent, :active]

## Implementing models like Customer can safely dump their fields
cust = Customer.new
cust.safe_dump
#=> {identifier: "anon", custid: "anon", email: nil, role: "customer", verified: nil, last_login: nil, locale: "", updated: nil, created: nil, stripe_customer_id: nil, stripe_subscription_id: nil, stripe_checkout_email: nil, plan: {planid: nil, source: "parts_unknown"}, secrets_created: "0", secrets_burned: "0", secrets_shared: "0", emails_sent: "0", active: false}

## Implementing models like Customer do have other fields
## that are by default considered not safe to dump.
cust = Customer.new(name: 'Lucy', custid: @email)

all_non_safe_fields = cust.instance_variables.map { |el|
  el.to_s[1..-1].to_sym # slice off the leading @
}.sort

p [cust.respond_to?(:suffix), cust.respond_to?(:db), cust.respond_to?(:ttl)]
p cust.class.safe_dump_fields

cust.class.safe_dump_fields.sort
##=> [:custid, :custom_domains, :email, :emails_sent, :feature_flags, :locale, :metadata, :reset_secret, :role, :secrets_burned, :secrets_created, :secrets_shared]

## Implementing models like Customer can rest assured knowing
## any other field not in the safe list will not be dumped.
cust = Customer.new
cust.instance_variable_set(:"@haircut", "coupe de longueuil")

all_safe_fields = cust.safe_dump.keys.sort

all_non_safe_fields = cust.instance_variables.map { |el|
  el.to_s[1..-1].to_sym # slice off the leading @
}.sort

# NOTE: Slight behaviour change as of 2024-08-15 while upgrading to Familia
# v1.0. The expected return value was `[:custid]` and has been updated to
# include `:role`. The naming of safe vs non-safe is a bit misleading: the
# fact that a field is returned as an instance variable just means that a
# value has been set for that field and has nothing to do with whether or
# not that field is safe to dump.
# The reason :role is present is a result of this change where we explicitly
# set a value for role an initialization time:
#
#   class Customer
#     def init
#       self.custid ||= 'anon'
#       self.role ||= 'customer'
#
#       # counter fields also added -- Aug 26
#     end
#   end
#

# Check if any of the non-safe fields are in the safe dump
all_non_safe_fields & all_safe_fields
#=>  [:custid, :emails_sent, :locale, :role, :secrets_burned, :secrets_created, :secrets_shared]
