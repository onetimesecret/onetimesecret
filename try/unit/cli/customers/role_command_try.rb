# try/unit/cli/customers/role_command_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots customers role (promote, demote, list)
#
# Covers:
# 1. Promoting a customer to colonel
# 2. Demoting a colonel to customer
# 3. Promoting an already-colonel user (no-op)
# 4. Demoting a user who is already a customer (no-op)
# 5. Admin and staff role changes via demote
# 6. Role validation rejects unknown roles
# 7. Email validation (nil, empty, non-existent)
# 8. Role index updates on promote/demote
#
# Run: bundle exec try try/unit/cli/customers/role_command_try.rb

ENV['AUTHENTICATION_MODE'] = 'simple'

require_relative '../../../support/test_helpers'

OT.boot! :cli
require 'onetime/cli'

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup with unique identifiers to avoid collisions
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create test customer fixtures with distinct roles
@regular_email = "regular_#{@test_suffix}@test.example.com"
@colonel_email = "colonel_#{@test_suffix}@test.example.com"
@admin_email = "admin_#{@test_suffix}@test.example.com"
@staff_email = "staff_#{@test_suffix}@test.example.com"

@regular = Onetime::Customer.create!(email: @regular_email)
@regular.role = 'customer'
@regular.verified = 'true'
@regular.save

@colonel = Onetime::Customer.create!(email: @colonel_email)
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@admin = Onetime::Customer.create!(email: @admin_email)
@admin.role = 'admin'
@admin.verified = 'true'
@admin.save

@staff = Onetime::Customer.create!(email: @staff_email)
@staff.role = 'staff'
@staff.verified = 'true'
@staff.save

# Valid roles constant from the command
@valid_roles = Onetime::CLI::CustomersRoleCommand::VALID_ROLES

# -------------------------------------------------------------------
# Helper methods that mirror the command's private logic without
# the interactive prompt or boot_application! call.
# -------------------------------------------------------------------

def promote_customer(email, target_role, force: true)
  unless @valid_roles.include?(target_role)
    return { success: false, error: "Invalid role '#{target_role}'" }
  end

  unless email && !email.to_s.empty?
    return { success: false, error: "Email address required for 'promote' action" }
  end

  unless Onetime::Customer.email_exists?(email)
    obscured = OT::Utils.obscure_email(email)
    return { success: false, error: "Customer not found: #{obscured}" }
  end

  customer = Onetime::Customer.find_by_email(email)
  old_role = customer.role.to_s

  if old_role == target_role
    return { success: true, no_op: true, message: "#{email} already has role '#{target_role}'" }
  end

  customer.role = target_role
  customer.save

  { success: true, no_op: false, old_role: old_role, new_role: target_role, customer: customer }
end

def demote_customer(email, force: true)
  unless email && !email.to_s.empty?
    return { success: false, error: "Email address required for 'demote' action" }
  end

  unless Onetime::Customer.email_exists?(email)
    obscured = OT::Utils.obscure_email(email)
    return { success: false, error: "Customer not found: #{obscured}" }
  end

  customer = Onetime::Customer.find_by_email(email)
  old_role = customer.role.to_s

  if old_role == 'customer'
    return { success: true, no_op: true, message: "#{email} already has role 'customer'" }
  end

  customer.role = 'customer'
  customer.save

  { success: true, no_op: false, old_role: old_role, new_role: 'customer', customer: customer }
end

def reset_role(email, target_role)
  cust = Onetime::Customer.find_by_email(email)
  cust.role = target_role
  cust.save
  cust.role.to_s
end

# TRYOUTS

# -------------------------------------------------------------------
# Command class basics
# -------------------------------------------------------------------

## CustomersRoleCommand exists and inherits from CLI Command
Onetime::CLI::CustomersRoleCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## CustomersRoleCommand is a Dry::CLI::Command
cmd = Onetime::CLI::CustomersRoleCommand.new
cmd.is_a?(Dry::CLI::Command)
#=> true

## VALID_ROLES contains all expected roles
@valid_roles
#=> ["colonel", "admin", "staff", "customer"]

# -------------------------------------------------------------------
# Promote: customer -> colonel
# -------------------------------------------------------------------

## Promoting a regular customer to colonel succeeds
@promote_result = promote_customer(@regular_email, 'colonel')
@promote_result[:success]
#=> true

## Promote result is not a no-op
@promote_result[:no_op]
#=> false

## Old role was customer
@promote_result[:old_role]
#=> "customer"

## New role is colonel
@promote_result[:new_role]
#=> "colonel"

## Customer record in Redis has updated role after promotion
Onetime::Customer.find_by_email(@regular_email).role.to_s
#=> "colonel"

## Reset regular back to customer after colonel promotion
reset_role(@regular_email, 'customer')
#=> "customer"

# -------------------------------------------------------------------
# Promote: customer -> admin
# -------------------------------------------------------------------

## Promoting a customer to admin succeeds
@admin_promo = promote_customer(@regular_email, 'admin')
@admin_promo[:success] && @admin_promo[:new_role] == 'admin'
#=> true

## Customer record in Redis reflects admin role
Onetime::Customer.find_by_email(@regular_email).role.to_s
#=> "admin"

## Reset regular back to customer after admin promotion
reset_role(@regular_email, 'customer')
#=> "customer"

# -------------------------------------------------------------------
# Promote: customer -> staff
# -------------------------------------------------------------------

## Promoting a customer to staff succeeds
@staff_promo = promote_customer(@regular_email, 'staff')
@staff_promo[:success] && @staff_promo[:new_role] == 'staff'
#=> true

## Customer record in Redis reflects staff role
Onetime::Customer.find_by_email(@regular_email).role.to_s
#=> "staff"

## Reset regular back to customer after staff promotion
reset_role(@regular_email, 'customer')
#=> "customer"

# -------------------------------------------------------------------
# Promote: already a colonel (no-op)
# -------------------------------------------------------------------

## Promoting a customer who is already a colonel is a no-op
@noop_result = promote_customer(@colonel_email, 'colonel')
@noop_result[:no_op]
#=> true

## The no-op message mentions already has role
@noop_result[:message].include?("already has role 'colonel'")
#=> true

## Colonel role remains unchanged in Redis
Onetime::Customer.find_by_email(@colonel_email).role.to_s
#=> "colonel"

# -------------------------------------------------------------------
# Demote: colonel -> customer
# -------------------------------------------------------------------

## Demoting a colonel to customer succeeds
@demote_result = demote_customer(@colonel_email)
@demote_result[:success]
#=> true

## Demote result is not a no-op
@demote_result[:no_op]
#=> false

## Old role was colonel
@demote_result[:old_role]
#=> "colonel"

## New role is customer
@demote_result[:new_role]
#=> "customer"

## Colonel record in Redis is now customer role
Onetime::Customer.find_by_email(@colonel_email).role.to_s
#=> "customer"

## Reset colonel back to colonel after demotion
reset_role(@colonel_email, 'colonel')
#=> "colonel"

# -------------------------------------------------------------------
# Demote: already a customer (no-op)
# -------------------------------------------------------------------

## Demoting a customer who already has role customer is a no-op
@demote_noop = demote_customer(@regular_email)
@demote_noop[:no_op]
#=> true

## The no-op message mentions already has role customer
@demote_noop[:message].include?("already has role 'customer'")
#=> true

# -------------------------------------------------------------------
# Demote: admin -> customer
# -------------------------------------------------------------------

## Demoting an admin produces a role change to customer
@admin_demote = demote_customer(@admin_email)
@admin_demote[:success] && @admin_demote[:old_role] == 'admin' && @admin_demote[:new_role] == 'customer'
#=> true

## Admin record in Redis is now customer
Onetime::Customer.find_by_email(@admin_email).role.to_s
#=> "customer"

## Reset admin back to admin after demotion
reset_role(@admin_email, 'admin')
#=> "admin"

# -------------------------------------------------------------------
# Demote: staff -> customer
# -------------------------------------------------------------------

## Demoting staff to customer succeeds
@staff_demote = demote_customer(@staff_email)
@staff_demote[:success] && @staff_demote[:old_role] == 'staff'
#=> true

## Staff record in Redis is now customer
Onetime::Customer.find_by_email(@staff_email).role.to_s
#=> "customer"

## Reset staff back to staff after demotion
reset_role(@staff_email, 'staff')
#=> "staff"

# -------------------------------------------------------------------
# Role validation: invalid role rejected
# -------------------------------------------------------------------

## Promoting to an invalid role returns an error
@invalid_result = promote_customer(@regular_email, 'superuser')
@invalid_result[:success]
#=> false

## Error mentions invalid role
@invalid_result[:error].include?("Invalid role")
#=> true

# -------------------------------------------------------------------
# Email validation: missing email
# -------------------------------------------------------------------

## Promote with nil email returns error
@nil_email = promote_customer(nil, 'colonel')
@nil_email[:success] == false && @nil_email[:error].include?("Email address required")
#=> true

## Demote with nil email returns error
@nil_demote = demote_customer(nil)
@nil_demote[:success] == false && @nil_demote[:error].include?("Email address required")
#=> true

# -------------------------------------------------------------------
# Email validation: non-existent customer
# -------------------------------------------------------------------

## Promote with non-existent email returns error
@missing = promote_customer("nobody_#{@test_suffix}@test.example.com", 'colonel')
@missing[:success] == false && @missing[:error].include?("Customer not found")
#=> true

## Demote with non-existent email returns error
@missing_demote = demote_customer("nobody_#{@test_suffix}@test.example.com")
@missing_demote[:success] == false && @missing_demote[:error].include?("Customer not found")
#=> true

# -------------------------------------------------------------------
# Role index: find_all_by_role after promotion
# -------------------------------------------------------------------

## Promote regular to colonel and verify role index includes them
promote_customer(@regular_email, 'colonel')
@colonel_emails = Onetime::Customer.find_all_by_role('colonel').map(&:email)
@colonel_emails.include?(@regular_email)
#=> true

## Role index still includes the original colonel after promoting another
@colonel_emails.include?(@colonel_email)
#=> true

## Reset regular after role index test
reset_role(@regular_email, 'customer')
#=> "customer"

# -------------------------------------------------------------------
# Role index: find_all_by_role after demotion
# -------------------------------------------------------------------

## Demote colonel and verify role index no longer includes them
demote_customer(@colonel_email)
@colonel_emails_after = Onetime::Customer.find_all_by_role('colonel').map(&:email)
@colonel_emails_after.include?(@colonel_email)
#=> false

## Reset colonel after role index demotion test
reset_role(@colonel_email, 'colonel')
#=> "colonel"

# TEARDOWN

[@regular_email, @colonel_email, @admin_email, @staff_email].each do |email|
  cust = Onetime::Customer.find_by_email(email)
  cust.destroy! if cust&.respond_to?(:destroy!) && cust.exists?
end
