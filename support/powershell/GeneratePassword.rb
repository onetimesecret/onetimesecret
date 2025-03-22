
# Namespace: System.Web.Security
# Membership.GeneratePassword(Int32, Int32) Method
#
# The GeneratePassword method is used to generate a random
# password and is most commonly used by the ResetPassword
# method implemented by a membership provider to reset the
# password for a user to a new, temporary password.
#
# The generated password only contains alphanumeric
# characters and the following punctuation marks:
# !@#$%^&*()_-+=[{]};:<>|./?. No hidden or non-printable
# control characters are included in the generated password.
#
# https://learn.microsoft.com/en-us/dotnet/api/system.web.security.membership.generatepassword?view=netframework-4.8.1#system-web-security-membership-generatepassword(system-int32-system-int32)
#
class PasswordGenerator
  LOWER_CASE = ('a'..'z').to_a
  UPPER_CASE = ('A'..'Z').to_a
  NUMBERS = ('0'..'9').to_a
  SPECIAL_CHARS = '!@#$%^&*()_-+=[{]};:<>|./?'.chars

  def self.generate(length = 12)
    all_chars = LOWER_CASE + UPPER_CASE + NUMBERS + SPECIAL_CHARS

    # Ensure at least one of each type
    password = [
      LOWER_CASE.sample,
      UPPER_CASE.sample,
      NUMBERS.sample,
      SPECIAL_CHARS.sample,
    ]

    # Fill the rest with random characters
    (length - password.count).times do
      password << all_chars.sample
    end

    # Shuffle the password to randomize the guaranteed characters' positions
    password.shuffle.join
  end

  def self.meets_criteria?(password)
    password.match?(/[a-z]/) &&
      password.match?(/[A-Z]/) &&
      password.match?(/\d/) &&
      password.match?(/[#{Regexp.escape(SPECIAL_CHARS.join)}]/)
  end
end

# Usage
password = PasswordGenerator.generate(5)
puts "Generated Password: #{password}"
puts "Meets Criteria: #{PasswordGenerator.meets_criteria?(password)}"
