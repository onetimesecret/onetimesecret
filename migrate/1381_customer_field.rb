# Quick Redis scan to find customers with missing/empty email fields
report_field = 'email'
redis_client = V2::Customer.redis
scan_pattern = "#{V2::Customer.prefix}:*:object"
cursor = "0"
batch_size = 5000
progress_size = batch_size*2

modified_count = 0
problem_customers = []
total_scanned = 0

dry_run = true

puts "Scanning for customers with empty #{report_field} fields... (dry_run: #{dry_run})"

loop do
  cursor, keys = redis_client.scan(cursor, match: scan_pattern, count: batch_size)
  total_scanned += keys.size

  keys.each do |key|
    custid = begin
      key.split(':')[1]
    rescue
      "unknown_from_#{key}"
    end
    email_value = redis_client.hget(key, report_field)
    if email_value.nil? || email_value.empty?
      problem_customers << { id: custid, key: key }
      next if dry_run
      modified_count += 1
    end
  end

  print "." if total_scanned % progress_size == 0 # Progress indicator
  break if cursor == "0"
end

empty_count = problem_customers.size

puts "\nScan complete: #{empty_count} out of #{total_scanned} customers missing #{report_field} field"
puts "#{modified_count} customers modified (dry_run: #{dry_run})"
puts "First 10 affected customers: #{problem_customers.first(10).map{ |c| c[:id] }.join(', ')}" if modified_count > 0
