# lib/onetime/models/customer/features/legacy_encrypted_fields.rb

module Onetime
  module Models
    module Features
      module LegacyEncryptedFields
        Familia::Base.add_feature self, :legacy_encrypted_fields

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.extend ClassMethods
          base.include InstanceMethods
          base.field :passphrase
          base.field :passphrase_encryption
          base.attr_reader :passphrase_temp
        end

        module ClassMethods
        end

        module InstanceMethods
          def encryption_key
            Onetime::Secret.encryption_key OT.global_secret, custid
          end

          def update_passphrase!(val)
            passphrase_encryption! '1'
            # Hold the unencrypted passphrase in memory for a short time
            # (which will basically be until this instance is garbage
            # collected) in case we need to repeat the save attempt on
            # error. TODO: Move to calling code in specific cases.
            @passphrase_temp = val
            update_passphrase(val)
            passphrase! @passphrase
          end

          # Allow for chaining API e.g. cust.update_passphrase('plop').custid
          def update_passphrase(val)
            @passphrase = BCrypt::Password.create(val, cost: 12).to_s
          end

          def has_passphrase?
            !passphrase.to_s.empty?
          end

          def passphrase?(guess)
            ret              = BCrypt::Password.new(passphrase) == guess
            @passphrase_temp = guess if ret # used to decrypt the value
            ret
          rescue BCrypt::Errors::InvalidHash => ex
            prefix = '[passphrase?]'
            OT.li "#{prefix} Invalid passphrase hash: #{ex.message}"
            (!guess.to_s.empty? && passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
          end
        end
      end
    end
  end
end

__END__

require 'bcrypt'
require 'benchmark'

# Sample password
password =  '58ww8zwt5tvt40cvmbmpqk4f7sklk4prk032dh3gwvbn6jkavk3elvb9qtrasa5'

# Define the range of cost factors to test
# cost factor 12: 0.285811 seconds
# cost factor 13: 0.565042 seconds
# cost factor 14: 1.125720 seconds
# cost factor 15: 2.241410 seconds
# cost factor 16: 4.488586 seconds
cost_factors = (12..16)

# Run the benchmark for each cost factor
puts "Using password: #{password}"
cost_factors.each do |cost|
  time = Benchmark.measure do
    passphrase = BCrypt::Password.create(password, cost: cost).to_s
  end
  puts "Cost factor #{cost}: #{time.real} seconds"
end
