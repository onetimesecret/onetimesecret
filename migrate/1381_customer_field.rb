# Quick Redis scan to find customers with missing/empty email fields
report_field = 'email'
redis_client = V2::Customer.redis
scan_pattern = "#{V2::Customer.prefix}:*:object"
cursor = "0"
batch_size = 5000
progress_size = batch_size/2

error_count = 0
modified_count = 0
problem_customers = []
total_scanned = 0
total_skipped = 0

dry_run = true

puts "Scanning for customers with empty #{report_field} fields... (dry_run: #{dry_run})"

# Verification step - test Redis connection
begin
  redis_client.ping
  puts "Redis connection verified"
rescue => ex
  puts "ERROR: Cannot connect to Redis: #{ex.message}"
  exit 1
end


loop do
  cursor, keys = redis_client.scan(cursor, match: scan_pattern, count: batch_size)
  total_scanned += keys.size

  keys.each do |key|
    # How the record is identified/stored in Redis
    redis_key_identifier = begin
      key.split(':')[1]
    rescue => ex
      error_count += 1
      puts "Error parsing key: #{key} (#{ex.message})"
      cursor = "0"
      break
    end

    record_data = begin
      redis_client.hgetall(key)

    rescue => ex
      error_count += 1
      puts "Error fetching data for #{key} (#{ex.message})"
      cursor = "0"
      break
    end

    record_identifier = record_data['custid']
    if record_identifier.to_s.empty?
      puts "Skipping #{key} (empty custid field)"
      total_skipped += 1
      next
    end

    if redis_key_identifier != record_identifier
      puts "Mismatch #{key} (mismatched custid field: #{record_identifier})"
      total_skipped += 1
      cursor = "0"
      break
    end

    field_value = record_data[report_field.to_s]
    if field_value.to_s.empty?
      problem_customers << { id: record_identifier, key: key }
      next if dry_run
      modified_count += 1
      redis_client.hset(key, report_field.to_s, record_identifier)
    end
  end

  print "." if total_scanned % progress_size == 0 # Progress indicator
  break if cursor == "0"
end

empty_count = problem_customers.size

puts "\nScan complete: #{empty_count} out of #{total_scanned} customers missing #{report_field} field"
puts "Errors: #{error_count}; Skipped: #{total_skipped}"
puts "#{modified_count} customers modified (dry_run: #{dry_run})"
puts "First 10 affected customers: #{problem_customers.first(10).map{ |c| c[:id] }.join(', ')}" if modified_count > 0
