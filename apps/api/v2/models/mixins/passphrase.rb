# apps/api/v2/models/mixins/passphrase.rb

module V2
  module Mixins

    # Passphrase
    #
    # Adds a passphrase field to the model.
    #
    module Passphrase
      def self.included(base)
        base.field :passphrase
        base.field :passphrase_encryption
      end

      attr_accessor :passphrase_temp

      def update_passphrase!(val)
        passphrase_encryption! '1'
        # Hold the unencrypted passphrase in memory for a short time
        # (which will basically be until this instance is garbage
        # collected) in case we need to repeat the save attempt on
        # error. TODO: Move to calling code in specific cases.
        @passphrase_temp = val
        passphrase! BCrypt::Password.create(val, cost: 12).to_s
      end

      # Allow for chaining API e.g. cust.update_passphrase('plop').custid
      def update_passphrase(val)
        update_passphrase! val
        self
      end

      def has_passphrase?
        !passphrase.to_s.empty?
      end

      def passphrase?(guess)
          ret              = BCrypt::Password.new(passphrase) == guess
          @passphrase_temp = guess if ret  # used to decrypt the value
          ret
      rescue BCrypt::Errors::InvalidHash => ex
          prefix = '[passphrase?]'
          OT.ld "#{prefix} Invalid passphrase hash: #{ex.message}"
          (!guess.to_s.empty? && passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
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
# cost factor 10: 0.085388 seconds
# cost factor 11: 0.122143 seconds
# cost factor 12: 0.230641 seconds
# cost factor 13: 0.462779 seconds
# cost factor 14: 0.922170 seconds
cost_factors = (10..14)

# Run the benchmark for each cost factor
puts "Using password: #{password}"
cost_factors.each do |cost|
  time = Benchmark.measure do
    passphrase = BCrypt::Password.create(password, cost: cost).to_s
  end
  puts "Cost factor #{cost}: #{time.real} seconds"
end
