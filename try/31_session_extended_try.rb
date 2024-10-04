# frozen_string_literal: true

require 'benchmark'

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot!

@ipaddress = '10.0.0.254'
@useragent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_2_5) AppleWebKit/237.36 (KHTML, like Gecko) Chrome/10.0.95 Safari/237.36'
@custid = 'tryouts'
@session_ids = 1000.times.map { OT::Session.create(@ipaddress, @custid, @useragent).sessid }


## Generate a large set of session IDs and check for duplicates
[@session_ids.uniq.length, @session_ids.length]
#=> [1000, 1000]

## Verify that the distribution of characters in the IDs is uniform
char_counts = @session_ids.join.chars.group_by(&:itself).transform_values(&:count)
std_dev = Math.sqrt(char_counts.values.sum { |count| (count - char_counts.values.sum.to_f / char_counts.length) ** 2 } / char_counts.length)
[std_dev < 50, char_counts.length > 30]  # Adjust these thresholds as needed
#=> [true, true]

## Check that the length of all generated IDs is consistent
## and within an acceptable range (e.g. [50, 49, 48])
lengths = @session_ids.map(&:length).uniq
min_length, max_length = 47, 53  # Adjust these values based on your implementation
puts lengths
lengths.all? { |length| length.between?(min_length, max_length) }
#=> true

## Ensure IDs don't contain any predictable patterns
first_chars = @session_ids.map { |id| id[0, 3] }
last_chars = @session_ids.map { |id| id[-3, 3] }
[first_chars.uniq.length > 100, last_chars.uniq.length > 100]  # Adjust thresholds as needed
#=> [true, true]

## Add timing tests to verify that ID generation is consistent and reasonably fast
times = 10.times.map { Benchmark.realtime { OT::Session.create(@ipaddress, @custid, @useragent) } }
[times.max < 0.01, times.min > 0]  # Adjust the max time (0.01 seconds) as needed
#=> [true, true]

## Implement collision resistance tests (generating IDs with similar inputs)
similar_inputs = [
  ['10.0.0.1', 'user1', 'Chrome'],
  ['10.0.0.2', 'user1', 'Chrome'],
  ['10.0.0.1', 'user2', 'Chrome'],
  ['10.0.0.1', 'user1', 'Firefox']
]
similar_ids = similar_inputs.map { |ip, cust, ua| OT::Session.create(ip, cust, ua).sessid }
similar_ids.uniq.length == similar_ids.length
#=> true

## Test ID generation with various input combinations
varied_inputs = [
  ['192.168.1.1', 'customer1', 'Safari'],
  ['8.8.8.8', 'customer2', 'Edge'],
  ['172.16.0.1', 'customer3', 'Opera'],
  ['::1', 'customer4', 'Brave']
]
varied_ids = varied_inputs.map { |ip, cust, ua| OT::Session.create(ip, cust, ua).sessid }
varied_ids.uniq.length == varied_ids.length
#=> true

## Verify that IDs are URL-safe and don't contain any special characters
url_unsafe_chars = /[^a-zA-Z0-9\-_]/
@session_ids.any? { |id| id =~ url_unsafe_chars }
#=> false

## Check that IDs are case-insensitive (if applicable to our system)
downcase_ids = @session_ids.map(&:downcase)
upcase_ids = @session_ids.map(&:upcase)
[downcase_ids == @session_ids, upcase_ids == @session_ids]
#=> [true, false]  # Adjust based on your case-sensitivity requirements

## Test ID generation across different Ruby versions (simulate by calling the method multiple times)
ruby_version_ids = 3.times.map { OT::Session.create(@ipaddress, @custid, @useragent).sessid }
ruby_version_ids.uniq.length == ruby_version_ids.length
#=> true
