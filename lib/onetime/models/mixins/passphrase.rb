# frozen_string_literal: true

module Onetime::Models
  module Passphrase
    attr_accessor :passphrase_temp
    def update_passphrase v
      self.passphrase_encryption = "1"
      @passphrase_temp = v
      self.passphrase = BCrypt::Password.create(v, :cost => 12).to_s
    end
    def has_passphrase?
      !passphrase.to_s.empty?
    end
    def passphrase? guess
      begin
        ret = BCrypt::Password.new(passphrase) == guess
        @passphrase_temp = guess if ret  # used to decrypt the value
        ret
      rescue BCrypt::Errors::InvalidHash => ex
        prefix = "[old-passphrase]"
        OT.ld "#{prefix} Invalid passphrase hash: #{ex.message}"
        (!guess.to_s.empty? && passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
      end
    end
  end
end
