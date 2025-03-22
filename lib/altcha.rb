# lib/altcha.rb

# Based on from: https://github.com/altcha-org/altcha-lib-rb
#
# NOTE: There were a few changes required to get verification
# working. I'll be submitting them via PR upstream and just
# including them here temporarily for convenience while
# working any other kinks out.

require 'openssl'
require 'base64'
require 'json'
require 'uri'
require 'time'

# Altcha module provides functions for creating and verifying ALTCHA challenges.
module Altcha
  # Contains algorithm type definitions for hashing.
  module Algorithm
    SHA1 = 'SHA-1'
    SHA256 = 'SHA-256'
    SHA512 = 'SHA-512'
  end

  # Default values for challenge generation.
  DEFAULT_MAX_NUMBER = 1_000_000
  DEFAULT_SALT_LENGTH = 12
  DEFAULT_ALGORITHM = Algorithm::SHA256

  # Class representing options for generating a challenge.
  class ChallengeOptions
    attr_accessor :algorithm, :max_number, :salt_length, :hmac_key, :salt, :number, :expires, :params
  end

  # Class representing a challenge with its attributes.
  class Challenge
    attr_accessor :algorithm, :challenge, :maxnumber, :salt, :signature

    # Converts the Challenge object to a JSON string.
    # @param options [Hash] options to customize JSON encoding.
    # @return [String] JSON representation of the Challenge object.
    def to_json(options = {})
      {
        algorithm: @algorithm,
        challenge: @challenge,
        maxnumber: @maxnumber,
        salt: @salt,
        signature: @signature
      }.to_json(options)
    end

    # Creates a Challenge object from a JSON string.
    # @param string [String] JSON string to parse.
    # @return [Challenge] Parsed Challenge object.
    def from_json(string)
      data = JSON.parse(string)
      new data['algorithm'], data['challenge'], data['maxnumber'], data['salt'], data['signature']
    end
  end

  # Class representing the payload of a challenge.
  Payload = Struct.new(:algorithm, :challenge, :number, :salt, :signature, :took) do
    #attr_accessor :algorithm, :challenge, :number, :salt, :signature

    # Converts the Payload object to a JSON string.
    # @param options [Hash] options to customize JSON encoding.
    # @return [String] JSON representation of the Payload object.
    def to_json(options = {})
      {
        algorithm: @algorithm,
        challenge: @challenge,
        number: @number,
        salt: @salt,
        signature: @signature
      }.to_json(options)
    end

    # Creates a Payload object from a JSON string.
    # @param string [String] JSON string to parse.
    # @return [Payload] Parsed Payload object.
    def from_json(string)
      data = JSON.parse(string)
      new data['algorithm'], data['verificationData'], data['signature'], data['verified']
    end
  end

  # Class representing the payload for server signatures.
  ServerSignaturePayload = Struct.new(:algorithm, :verification_data, :signature, :verified, :challenge, :number, :salt, :took) do
    #attr_accessor :algorithm, :verification_data, :signature, :verified

    # Converts the ServerSignaturePayload object to a JSON string.
    # @param options [Hash] options to customize JSON encoding.
    # @return [String] JSON representation of the ServerSignaturePayload object.
    def to_json(options = {})
      {
        algorithm: @algorithm,
        verificationData: @verification_data,
        signature: @signature,
        verified: @verified
      }.to_json(options)
    end

    # Creates a ServerSignaturePayload object from a JSON string.
    # @param string [String] JSON string to parse.
    # @return [ServerSignaturePayload] Parsed ServerSignaturePayload object.
    def from_json(string)
      data = JSON.parse(string)
      new data['algorithm'], data['verificationData'], data['signature'], data['verified']
    end
  end

  # Class for verifying server signatures, containing various data points.
  ServerSignatureVerificationData = Struct.new(:classification, :country, :detected_language, :email, :expire, :fields, :fields_hash, :ip_address, :reasons, :score, :time, :verified)
    #attr_accessor :classification, :country, :detected_language, :email, :expire, :fields, :fields_hash,
    #:ip_address, :reasons, :score, :time, :verified

  # Class representing the solution to a challenge.
  class Solution
    attr_accessor :number, :took
  end

  # Generates a random byte array of the specified length.
  # @param length [Integer] The length of the byte array to generate.
  # @return [String] The generated random byte array.
  def self.random_bytes(length)
    OpenSSL::Random.random_bytes(length)
  end

  # Generates a random integer between 0 and the specified maximum (inclusive).
  # @param max [Integer] The upper bound for the random integer.
  # @return [Integer] The generated random integer.
  def self.random_int(max)
    rand(max + 1)
  end

  # Hashes the input data using the specified algorithm and returns the hexadecimal representation of the hash.
  # @param algorithm [String] The hashing algorithm to use (e.g., SHA-1, SHA-256, SHA-512).
  # @param data [String] The data to hash.
  # @return [String] The hexadecimal representation of the hashed data.
  def self.hash_hex(algorithm, data)
    hash = hash(algorithm, data)
    hash.unpack1('H*')
  end

  # Hashes the input data using the specified algorithm.
  # @param algorithm [String] The hashing algorithm to use (e.g., SHA-1, SHA-256, SHA-512).
  # @param data [String] The data to hash.
  # @return [String] The binary hash of the data.
  # @raise [ArgumentError] If an unsupported algorithm is specified.
  def self.hash(algorithm, data)
    case algorithm
    when Algorithm::SHA1
      OpenSSL::Digest::SHA1.digest(data)
    when Algorithm::SHA256
      OpenSSL::Digest::SHA256.digest(data)
    when Algorithm::SHA512
      OpenSSL::Digest::SHA512.digest(data)
    else
      raise ArgumentError, "Unsupported algorithm: #{algorithm}"
    end
  end

  # Computes the HMAC of the input data using the specified algorithm and key, and returns the hexadecimal representation.
  # @param algorithm [String] The hashing algorithm to use (e.g., SHA-1, SHA-256, SHA-512).
  # @param data [String] The data to hash.
  # @param key [String] The key for the HMAC.
  # @return [String] The hexadecimal representation of the HMAC.
  def self.hmac_hex(algorithm, data, key)
    hmac = hmac_hash(algorithm, data, key)
    hmac.unpack1('H*')
  end

  # Computes the HMAC of the input data using the specified algorithm and key.
  # @param algorithm [String] The hashing algorithm to use (e.g., SHA-1, SHA-256, SHA-512).
  # @param data [String] The data to hash.
  # @param key [String] The key for the HMAC.
  # @return [String] The binary HMAC of the data.
  # @raise [ArgumentError] If an unsupported algorithm is specified.
  def self.hmac_hash(algorithm, data, key)
    digest_class = case algorithm
                   when Algorithm::SHA1
                     OpenSSL::Digest::SHA1
                   when Algorithm::SHA256
                     OpenSSL::Digest::SHA256
                   when Algorithm::SHA512
                     OpenSSL::Digest::SHA512
                   else
                     raise ArgumentError, "Unsupported algorithm: #{algorithm}"
                   end
    OpenSSL::HMAC.digest(digest_class.new, key, data)
  end

  # Creates a challenge for the client to solve based on the provided options.
  # @param options [ChallengeOptions] Options for generating the challenge.
  # @return [Challenge] The generated Challenge object.
  def self.create_challenge(options)
    algorithm = options.algorithm || DEFAULT_ALGORITHM
    max_number = options.max_number || DEFAULT_MAX_NUMBER
    salt_length = options.salt_length || DEFAULT_SALT_LENGTH

    params = options.params || {}
    params['expires'] = options.expires.to_i if options.expires

    salt = options.salt || random_bytes(salt_length).unpack1('H*')
    salt += "?#{URI.encode_www_form(params)}" unless params.empty?

    number = options.number || random_int(max_number)

    challenge_str = "#{salt}#{number}"
    challenge = hash_hex(algorithm, challenge_str)
    signature = hmac_hex(algorithm, challenge, options.hmac_key)

    Challenge.new.tap do |c|
      c.algorithm = algorithm
      c.challenge = challenge
      c.maxnumber = max_number
      c.salt = salt
      c.signature = signature
    end
  end

  # Verifies the solution provided by the client.
  # @param payload [String, Payload] The payload to verify, either as a base64 encoded JSON string or a Payload instance.
  # @param hmac_key [String] The key used for HMAC verification.
  # @param check_expires [Boolean] Whether to check if the challenge has expired.
  # @return [Boolean] True if the solution is valid, false otherwise.
  def self.verify_solution(payload, hmac_key, check_expires = true)
    # Attempt to handle payload as a base64 encoded JSON string or as a Payload instance

    # Decode and parse base64 JSON string if it's a String
    if payload.is_a?(String)
      decoded_payload = Base64.decode64(payload)
      payload = JSON.parse(decoded_payload, object_class: Payload)
    end

    # Ensure payload is an instance of Payload
    return false unless payload.is_a?(Payload)

    required_attributes = %i[algorithm challenge number salt signature]
    required_attributes.each do |attr|
      value = payload.send(attr)
      return false if value.nil? || value.to_s.strip.empty?
    end

    # Extract expiration time if checking expiration
    if check_expires && payload.salt.include?('?')
      expires = URI.decode_www_form(payload.salt.split('?').last).to_h['expires'].to_i
      return false if expires && Time.now.to_i > expires
    end

    # Convert payload to ChallengeOptions
    challenge_options = ChallengeOptions.new.tap do |co|
      co.algorithm = payload.algorithm
      co.hmac_key = hmac_key
      co.number = payload.number
      co.salt = payload.salt
    end

    # Create expected challenge and compare with the provided payload
    expected_challenge = create_challenge(challenge_options)
    expected_challenge.challenge == payload.challenge && expected_challenge.signature == payload.signature
  rescue ArgumentError, JSON::ParserError
    # Handle specific exceptions for invalid Base64 or JSON
    false
  end

  # Extracts parameters from the payload's salt.
  # @param payload [Payload] The payload containing the salt.
  # @return [Hash] Parameters extracted from the payload's salt.
  def self.extract_params(payload)
    URI.decode_www_form(payload.salt.split('?').last).to_h
  end

  # Verifies the hash of form fields.
  # @param form_data [Hash] The form data to verify.
  # @param fields [Array<String>] The fields to include in the hash.
  # @param fields_hash [String] The expected hash of the fields.
  # @param algorithm [String] The hashing algorithm to use.
  # @return [Boolean] True if the fields hash matches, false otherwise.
  def self.verify_fields_hash(form_data, fields, fields_hash, algorithm)
    lines = fields.map { |field| form_data[field].to_a.first.to_s }
    joined_data = lines.join("\n")
    computed_hash = hash_hex(algorithm, joined_data)
    computed_hash == fields_hash
  end

  # Verifies the server's signature.
  #
  # @param payload [String, ServerSignaturePayload] The payload to verify,
  #   either as a base64 encoded JSON string or a ServerSignaturePayload
  #   instance.
  #
  # @param hmac_key [String] The key used for HMAC verification.
  #
  # @return [Array<Boolean, ServerSignatureVerificationData>] A tuple where
  #   the first element is true if the signature is valid, and the second
  #   element is the verification data.
  #
  def self.verify_server_signature(payload, hmac_key)
    if payload.nil?
      OT.ld "[verify_server_signature] Payload is nil"
      return [false, nil]
    end

    # Decode and parse base64 JSON string if it's a String
    if payload.is_a?(String)
      decoded_payload = Base64.decode64(payload)
      payload = JSON.parse(decoded_payload, object_class: ServerSignaturePayload)
    end

    # Ensure payload is an instance of ServerSignaturePayload
    return [false, nil] unless payload.is_a?(ServerSignaturePayload)

    required_attributes = %i[algorithm verification_data signature verified]
    required_attributes.each do |attr|
      value = payload.send(attr)
      return false if value.nil? || value.to_s.strip.empty?
    end

    hash_data = hash(payload.algorithm, payload.verification_data)
    expected_signature = hmac_hex(payload.algorithm, hash_data, hmac_key)

    params = URI.decode_www_form(payload.verification_data).to_h
    verification_data = ServerSignatureVerificationData.new.tap do |v|
      v.classification = params['classification'] || nil
      v.country = params['country'] || nil
      v.detected_language = params['detectedLanguage'] || nil
      v.email = params['email'] || nil
      v.expire = params['expire'] ? params['expire'].to_i : nil
      v.fields = params['fields'] ? params['fields'].split(',') : nil
      v.reasons = params['reasons'] ? params['reasons'].split(',') : nil
      v.score = params['score'] ? params['score'].to_f : nil
      v.time = params['time'] ? params['time'].to_i : nil
      v.verified = params['verified'] == 'true'
    end

    now = Time.now.to_i
    is_verified = payload.verified &&
                  verification_data.verified &&
                  (verification_data.expire.nil? || verification_data.expire > now) &&
                  payload.signature == expected_signature

    [is_verified, verification_data]
  rescue ArgumentError, JSON::ParserError => e
    # Handle specific exceptions for invalid Base64 or JSON
    puts "Error decoding or parsing payload: #{e.message}"
    false
  end

  # Solves a challenge by iterating over possible solutions.
  # @param challenge [String] The challenge to solve.
  # @param salt [String] The salt used in the challenge.
  # @param algorithm [String] The hashing algorithm used.
  # @param max [Integer] The maximum number to try.
  # @param start [Integer] The starting number to try.
  # @return [Solution, nil] The solution if found, or nil if not.
  def self.solve_challenge(challenge, salt, algorithm, max, start)
    algorithm ||= Algorithm::SHA256
    max ||= DEFAULT_MAX_NUMBER
    start ||= 0

    start_time = Time.now

    (start..max).each do |n|
      hash = hash_hex(algorithm, "#{salt}#{n}")
      if hash == challenge
        return Solution.new.tap do |s|
          s.number = n
          s.took = Time.now - start_time
        end
      end
    end

    nil
  end
end
