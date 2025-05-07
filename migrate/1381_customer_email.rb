# /dev/null/irb_customer_email_check_scan.rb
# Ensure your application environment and models are loaded before running this.
# For example, in a Rails app, you might run `rails console`.
# For other Ruby apps, load the necessary setup files (e.g., 'config/environment.rb').

report_field_name = 'email' # or: email, identifier etc

puts "Starting SCAN-based scan of V2::Customer records for empty/non-existent #{report_field_name} fields..."

empty_report_field_count = 0
customers_with_issues = []
total_keys_scanned = 0
scan_loops = 0

# Get the Redis client instance.
# This might be V2::Customer.redis, Onetime::App.redis, or OT.redis
# depending on how it's configured in your application.
# Assuming V2::Customer.redis is available as per Familia models.
redis_client = V2::Customer.redis

# Define the pattern for customer object keys.
# Familia::Horreum stores objects with a key pattern like `prefix:identifier:object`.
# For V2::Customer, the prefix is 'customer'.
customer_key_pattern = "#{V2::Customer.prefix}:*:object"
cursor = "0"
batch_size = 2500 # Adjust batch size as needed

loop do
  scan_loops += 1
  cursor, keys = redis_client.scan(cursor, match: customer_key_pattern, count: batch_size)

  keys.each do |customer_key|
    total_keys_scanned += 1

    # Extract custid from the key.
    # Example key: "customer:somecustid:object"
    parts = customer_key.split(':')
    custid = parts.length > 2 ? parts[1] : "unknown_custid_from_key_#{customer_key}"

    # Directly fetch the report_field_name field from the Redis hash.
    # The `V2::Customer` model defines `field report_field`, so it's stored under the report_field_name hash key.
    report_field_value = redis_client.hget(customer_key, report_field_name)

    # Check if the report field is nil (non-existent in Redis hash) or an empty string.
    next unless report_field_value.nil? || report_field_value.empty?
    empty_report_field_count += 1
    customers_with_issues << { custid: custid, redis_key: customer_key, report_field_value: report_field_value }

    # You can uncomment the line below for immediate feedback during the loop:
    # puts "INFO: Customer key='#{customer_key}' (custid: #{custid}) has report_field_value: '#{report_field_value.inspect}'"
  end

  # Optional: print progress for very large datasets
  # if total_keys_scanned % (batch_size * 10) == 0 # e.g., every 10 batches
  #   puts "Processed #{total_keys_scanned} keys so far..."
  # end

  break if cursor == "0" # SCAN iteration is complete when cursor returns to "0"
end

puts "\nScan complete."
puts "--------------------------------------------------"
puts "Total Redis keys scanned matching pattern '#{customer_key_pattern}': #{total_keys_scanned}"
puts "Number of SCAN loops: #{scan_loops}"
puts "Number of customers with an empty or non-existent report field: #{empty_report_field_count}"
puts "--------------------------------------------------"

if empty_report_field_count > 0
  puts "\nDetails of customers with issues:"
  customers_with_issues.each do |info|
    puts "  - CustID: #{info[:custid].inspect}, Redis Key: #{info[:redis_key].inspect}, Report Field Value: #{info[:report_field_value].inspect}"
  end
else
  puts "\nNo customers found with empty or non-existent #{report_field_name} fields."
end

# If you need to return the count for further use in IRB:
empty_report_field_count
