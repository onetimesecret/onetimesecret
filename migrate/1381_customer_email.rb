# Quick Redis scan to find customers with missing/empty email fields
report_field = 'email'
redis_client = V2::Customer.redis
scan_pattern = "#{V2::Customer.prefix}:*:object"
cursor = "0"
batch_size = 5000
progress_size = batch_size*2

empty_count = 0
problem_customers = []
total_scanned = 0

puts "Scanning for customers with empty #{report_field} fields..."

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
      empty_count += 1
      problem_customers << { id: custid, key: key }
    end
  end

  print "." if total_scanned % progress_size == 0 # Progress indicator
  break if cursor == "0"
end

puts "\nScan complete: #{empty_count}/#{total_scanned} customers missing email"
puts "First 10 affected customers: #{problem_customers.first(10).map{ |c| c[:id] }.join(', ')}" if empty_count > 0
