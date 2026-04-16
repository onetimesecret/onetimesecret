# Raw Email Field Serialization

## Overview

Some customer records have the `email` field stored as a raw string instead of a Familia v2 JSON-serialized string. In Familia v2, all hash field values are JSON-encoded: strings are wrapped in double quotes (`"\"user@example.com\""`). A raw value like `"user@example.com"` (no wrapping quotes) violates this contract.

The app continues to function because `deserialize_value` has a fallback that catches JSON parse failures on bare strings, but each load emits a "Legacy plain string" instrumentation warning.

## How It Happened

`apps/web/auth/migrations/007_normalize_customer_emails.rb:148` lowercased mixed-case emails via raw Redis writes:

```ruby
redis.hset(customer_key, 'email', lowercase_email)
```

This bypasses `Familia::Horreum#serialize_value`, which wraps strings in JSON double quotes. Only customers with mixed-case email addresses were affected (10 of 604).

Corroborating evidence: the `contact_email` field on each affected customer's Organization still has the original mixed-case value, confirming these are exactly the records touched by the normalization migration.

## Diagnosis

### Count affected records

From `bin/console`:

```ruby
raw=0; total=0; OT::Customer.dbclient.scan_each(match: 'customer:*:object', count: 200){|k| total+=1; v=OT::Customer.dbclient.hget(k,'email'); raw+=1 if v && !v.empty? && !v.start_with?('"')}; puts "#{raw}/#{total} customers have raw email"
```

Result: `10/604 customers have raw email`

### List affected records with timestamps

```ruby
OT::Customer.dbclient.scan_each(match: 'customer:*:object', count: 200){|k| v=OT::Customer.dbclient.hget(k,'email'); next unless v && !v.empty? && !v.start_with?('"'); c,u=OT::Customer.dbclient.hmget(k,'created','updated'); puts "#{k} email=#{v} created=#{Time.at(c.to_f)} updated=#{Time.at(u.to_f)}"}; nil
```

### Confirm cause by comparing with org contact_email

```ruby
orgs={}; OT::Customer.dbclient.scan_each(match: 'organization:*:object', count: 200){|k| o=OT::Customer.dbclient.hget(k,'owner_id'); ce=OT::Customer.dbclient.hget(k,'contact_email'); orgs[o.to_s.tr('"','')]=ce if o}; OT::Customer.dbclient.scan_each(match: 'customer:*:object', count: 200){|k| v=OT::Customer.dbclient.hget(k,'email'); next unless v && !v.empty? && !v.start_with?('"'); c,u=OT::Customer.dbclient.hmget(k,'created','updated'); objid=OT::Customer.dbclient.hget(k,'objid').to_s.tr('"',''); ce=orgs[objid]; puts "#{objid} email=#{v} contact_email=#{ce} created=#{Time.at(c.to_f)} updated=#{Time.at(u.to_f)}"}; nil
```

Every affected record had a mixed-case `contact_email` on its Organization, confirming the email normalization migration as the source.

## Resolution

### Step 1: Repair the 10 records

From `bin/console`, wrap each raw email value in JSON double quotes:

```ruby
fixed=0; OT::Customer.dbclient.scan_each(match: 'customer:*:object', count: 200){|k| v=OT::Customer.dbclient.hget(k,'email'); next unless v && !v.empty? && !v.start_with?('"'); OT::Customer.dbclient.hset(k, 'email', "\"#{v}\""); fixed+=1}; puts "Fixed #{fixed} records"
```

### Step 2: Verify

Re-run the count query:

```ruby
raw=0; total=0; OT::Customer.dbclient.scan_each(match: 'customer:*:object', count: 200){|k| total+=1; v=OT::Customer.dbclient.hget(k,'email'); raw+=1 if v && !v.empty? && !v.start_with?('"')}; puts "#{raw}/#{total} customers have raw email"
```

Expected: `0/604 customers have raw email`

## Related

- GitHub issue: #3016
