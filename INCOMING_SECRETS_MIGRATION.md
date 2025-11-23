# Incoming Secrets Feature - Migration Guide for Develop Branch

**Version:** develop branch
**Feature Source:** PR #2016 from main branch
**Date:** 2025-11-23

## Overview

This document provides a complete implementation guide for porting the Incoming Secrets feature from the `main` branch to the `develop` branch. The feature allows anonymous users to send encrypted secrets to pre-configured recipients via a web form, with email notifications sent to recipients.

## Table of Contents

1. [Backend Changes](#backend-changes)
2. [Frontend Changes](#frontend-changes)
3. [Configuration Changes](#configuration-changes)
4. [Email Templates](#email-templates)
5. [Tests](#tests)
6. [Infrastructure Fixes](#infrastructure-fixes)
7. [Implementation Checklist](#implementation-checklist)

---

## Backend Changes

### 1. API Controllers

#### File: `apps/api/v2/controllers/incoming.rb` (NEW)

Create a new controller for incoming secrets endpoints:

```ruby
# apps/api/v2/controllers/incoming.rb

require_relative 'base'
require_relative '../logic/incoming'

module V2
  module Controllers
    class Incoming
      include V2::Controllers::Base

      @check_utf8 = true
      @check_uri_encoding = true

      def get_config
        retrieve_records(V2::Logic::Incoming::GetConfig, allow_anonymous: true)
      end

      def create_secret
        process_action(
          V2::Logic::Incoming::CreateIncomingSecret,
          "Incoming secret created successfully.",
          "Incoming secret could not be created.",
          allow_anonymous: true,
        )
      end

      def validate_recipient
        retrieve_records(V2::Logic::Incoming::ValidateRecipient, allow_anonymous: true)
      end
    end
  end
end
```

#### File: `apps/api/v2/controllers.rb` (MODIFY)

Add the incoming controller to the requires list:

```ruby
# Near the top with other controller requires
require_relative 'controllers/incoming'
```

### 2. API Logic Classes

#### File: `apps/api/v2/logic/incoming.rb` (NEW)

Create the incoming logic namespace:

```ruby
# apps/api/v2/logic/incoming.rb

require_relative 'incoming/get_config'
require_relative 'incoming/validate_recipient'
require_relative 'incoming/create_incoming_secret'

module V2::Logic
  module Incoming
    # Incoming secrets logic classes
  end
end
```

#### File: `apps/api/v2/logic/incoming/get_config.rb` (NEW)

```ruby
# apps/api/v2/logic/incoming/get_config.rb

require_relative '../base'

module V2::Logic
  module Incoming
    class GetConfig < V2::Logic::Base
      attr_reader :greenlighted, :config_data

      def process_params
        # No params needed for get_config
      end

      def raise_concerns
        # Check if feature is enabled
        incoming_config = OT.conf.dig(:features, :incoming) || {}
        unless incoming_config[:enabled]
          raise_form_error "Incoming secrets feature is not enabled"
        end

        limit_action :get_page
      end

      def process
        incoming_config = OT.conf.dig(:features, :incoming) || {}

        # Use hashed recipients to prevent email exposure
        @config_data = {
          enabled: incoming_config[:enabled] || false,
          memo_max_length: incoming_config[:memo_max_length] || 50,
          default_ttl: incoming_config[:default_ttl] || 604800,
          recipients: OT.incoming_public_recipients  # Returns hashed version
        }

        OT.ld "[IncomingConfig] Returning #{@config_data[:recipients].size} recipients (hashed)"

        @greenlighted = true
      end

      def success_data
        {
          config: config_data
        }
      end
    end
  end
end
```

#### File: `apps/api/v2/logic/incoming/validate_recipient.rb` (NEW)

```ruby
# apps/api/v2/logic/incoming/validate_recipient.rb

require_relative '../base'

module V2::Logic
  module Incoming
    class ValidateRecipient < V2::Logic::Base
      attr_reader :greenlighted, :recipient_hash, :is_valid

      def process_params
        @recipient_hash = params[:recipient].to_s.strip
      end

      def raise_concerns
        # Check if feature is enabled
        incoming_config = OT.conf.dig(:features, :incoming) || {}
        unless incoming_config[:enabled]
          raise_form_error "Incoming secrets feature is not enabled"
        end

        raise_form_error "Recipient hash is required" if recipient_hash.empty?

        limit_action :get_page
      end

      def process
        # Validate that the hash exists in our lookup table
        @is_valid = !OT.lookup_incoming_recipient(recipient_hash).nil?
        @greenlighted = true
      end

      def success_data
        {
          recipient: recipient_hash,
          valid: is_valid
        }
      end
    end
  end
end
```

#### File: `apps/api/v2/logic/incoming/create_incoming_secret.rb` (NEW)

```ruby
# apps/api/v2/logic/incoming/create_incoming_secret.rb

require_relative '../base'

module V2::Logic
  module Incoming
    class CreateIncomingSecret < V2::Logic::Base
      attr_reader :memo, :secret_value, :recipient_email, :recipient_hash, :ttl, :passphrase
      attr_reader :metadata, :secret, :greenlighted

      def process_params
        # All parameters are passed in the :secret hash like other V2 endpoints
        @payload = params[:secret] || {}
        raise_form_error "Incorrect payload format" if @payload.is_a?(String)

        incoming_config = OT.conf.dig(:features, :incoming) || {}

        # Extract and validate memo
        memo_max = incoming_config[:memo_max_length] || 50
        @memo = @payload[:memo].to_s.strip[0...memo_max]

        # Extract secret value
        @secret_value = @payload[:secret].to_s

        # Extract recipient hash instead of email
        @recipient_hash = @payload[:recipient].to_s.strip

        # Look up actual email from hash
        @recipient_email = OT.lookup_incoming_recipient(@recipient_hash)

        OT.ld "[IncomingSecret] Recipient hash: #{@recipient_hash} -> #{@recipient_email ? OT::Utils.obscure_email(@recipient_email) : 'not found'}"

        # Set TTL from config or use default
        @ttl = incoming_config[:default_ttl] || 604_800 # 7 days

        # Set passphrase from config (can be nil)
        @passphrase = incoming_config[:default_passphrase]
      end

      def raise_concerns
        # Check if feature is enabled
        incoming_config = OT.conf.dig(:features, :incoming) || {}
        unless incoming_config[:enabled]
          raise_form_error "Incoming secrets feature is not enabled"
        end

        # Validate required fields (memo is optional)
        raise_form_error "Secret content is required" if secret_value.empty?
        raise_form_error "Recipient is required" if @recipient_hash.to_s.empty?

        # Validate recipient hash exists and maps to valid email
        if @recipient_email.nil?
          OT.warn "[IncomingSecret] Invalid recipient hash attempted: #{@recipient_hash}"
          raise_form_error "Invalid recipient"
        end

        unless recipient_email.to_s.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
          OT.le "[IncomingSecret] Lookup returned invalid email for hash: #{@recipient_hash}"
          raise_form_error "Invalid recipient configuration"
        end

        # Apply rate limits
        limit_action :create_secret
        limit_action :email_recipient
      end

      def process
        # Create and encrypt secret using V2 pattern
        create_and_encrypt_secret

        # Update stats
        update_customer_stats

        # Send notification email
        send_recipient_notification

        @greenlighted = metadata.valid? && secret.valid?
      end

      def success_data
        {
          success: greenlighted,
          record: {
            metadata: metadata.safe_dump,
            secret: secret.safe_dump,
          },
          details: {
            memo: memo,
            recipient: recipient_hash,  # Return hash, not email
          },
        }
      end

      def form_fields
        {
          memo: memo,
          secret: secret_value,
          recipient: recipient_hash,  # Return hash, not email
        }
      end

      private

      def create_and_encrypt_secret
        # Use V2::Secret.spawn_pair to create linked secret and metadata
        @metadata, @secret = V2::Secret.spawn_pair cust.custid, nil

        # Store incoming-specific fields
        metadata.memo = memo
        metadata.recipients = recipient_email

        # Apply passphrase if configured
        unless passphrase.to_s.empty?
          secret.update_passphrase passphrase
          metadata.passphrase = secret.passphrase
        end

        # Encrypt the secret value
        secret.encrypt_value secret_value, size: plan.options[:size]

        # Set TTLs
        metadata.ttl = ttl * 2
        secret.ttl = ttl
        metadata.lifespan = metadata.ttl.to_i
        metadata.secret_ttl = secret.ttl.to_i
        secret.lifespan = secret.ttl.to_i

        # Store shortkey in metadata
        metadata.secret_shortkey = secret.shortkey

        # Save both
        secret.save
        metadata.save
      end

      def update_customer_stats
        # Update customer stats if not anonymous
        unless cust.anonymous?
          cust.add_metadata metadata
          cust.increment_field :secrets_created
        end

        # Update global stats
        V2::Customer.global.increment_field :secrets_created
        V2::Logic.stathat_count("Secrets", 1)
      end

      def send_recipient_notification
        return if recipient_email.nil? || recipient_email.empty?

        # Use a specialized template for incoming secrets
        klass = OT::Mail::IncomingSecretNotification

        # Create an anonymous customer object for the sender
        # This is needed for the deliver_by_email method signature
        anon_cust = V2::Customer.new(custid: 'anon')

        # Send the email using the existing delivery mechanism
        # Pass memo as additional parameter
        metadata.deliver_by_email(anon_cust, locale, secret, recipient_email, klass)

        OT.info "[IncomingSecret] Email notification sent to #{OT::Utils.obscure_email(recipient_email)} for secret #{secret.key}"
      rescue => e
        OT.le "[IncomingSecret] Failed to send email notification: #{e.message}"
        # Don't raise - email failure shouldn't prevent secret creation
      end
    end
  end
end
```

**Note:** The incoming logic is NOT required in `apps/api/v2/logic.rb`. The controller handles its own requires (see above where it includes `require_relative '../logic/incoming'`).

### 3. API Routes

#### File: `apps/api/v2/routes` (MODIFY)

Add incoming routes (note: routes should NOT include `/api/v2` prefix as it's handled by the routing system):

```ruby
# Incoming secrets endpoints
GET    /incoming/config                           V2::Controllers::Incoming#get_config
POST   /incoming/secret                           V2::Controllers::Incoming#create_secret
POST   /incoming/validate                         V2::Controllers::Incoming#validate_recipient
```

### 4. Web Routes

#### File: `apps/web/core/routes` (MODIFY)

Add incoming web routes (note: uses SPA pattern where all routes point to Page#index and Vue Router handles frontend routing):

```ruby
# Incoming secrets web routes
GET   /incoming                                  Core::Controllers::Page#index
GET   /incoming/*                                Core::Controllers::Page#index
```

### 5. Models

#### File: `apps/api/v2/models/metadata.rb` (MODIFY)

Add the `memo` field to the Metadata model:

```ruby
# Add to the field declarations:
field :memo

# Add to the @safe_dump_fields array:
@safe_dump_fields = [
  # ... existing fields ...
  :recipients,
  :memo,  # Add this line
  # ... rest of fields ...
]
```

### 6. Configuration

#### File: `lib/onetime/config.rb` (MODIFY)

Add default incoming features configuration:

```ruby
# In the DEFAULTS hash, add to the existing structure:
features: {
  incoming: {
    enabled: false,
    memo_max_length: 50,
    default_ttl: 604800,
    default_passphrase: nil,
    recipients: [],
  },
},
```

### 7. Initializers

#### File: `lib/onetime/initializers/setup_incoming_recipients.rb` (NEW)

```ruby
# frozen_string_literal: true

require 'digest/sha2'

module Onetime
  module Initializers

    # Sets up recipient hashing for the incoming secrets feature.
    # Processes raw email addresses from config and creates:
    # 1. A lookup table mapping hashes to emails (for backend)
    # 2. Public recipient list with hashes only (for frontend)
    #
    # This prevents email addresses from being exposed in API responses
    # while still allowing the backend to send notifications.
    def setup_incoming_recipients
      return unless OT.conf.dig(:features, :incoming, :enabled)

      raw_recipients = OT.conf.dig(:features, :incoming, :recipients) || []

      # Create lookup tables
      recipient_lookup = {}
      public_recipients = []

      raw_recipients.each do |recipient|
        email = recipient[:email]
        name = recipient[:name] || email.split('@').first

        # Generate a stable hash for this email
        # Use site secret as salt to ensure consistency across restarts
        site_secret = OT.conf[:site][:secret] || 'default-secret'
        hash_key = Digest::SHA256.hexdigest("#{email}:#{site_secret}")[0..15]

        # Store for backend lookup
        recipient_lookup[hash_key] = email

        # Store for frontend display (without email)
        public_recipients << {
          hash: hash_key,
          name: name
        }

        OT.info "[IncomingSecrets] Registered recipient: #{name} (#{OT::Utils.obscure_email(email)})"
      end

      # Store in class instance variables for quick access
      OT.instance_variable_set(:@incoming_recipient_lookup, recipient_lookup.freeze)
      OT.instance_variable_set(:@incoming_public_recipients, public_recipients.freeze)

      OT.info "[IncomingSecrets] Initialized #{recipient_lookup.size} recipients"
    end

  end
end

module Onetime
  class << self

    # Returns the lookup table mapping hashes to email addresses
    # @return [Hash<String, String>] Hash mapping recipient hashes to emails
    def incoming_recipient_lookup
      @incoming_recipient_lookup || {}
    end

    # Returns the public recipients list (hashes and names only, no emails)
    # @return [Array<Hash>] Array of hashes with :hash and :name keys
    def incoming_public_recipients
      @incoming_public_recipients || []
    end

    # Look up an email address from a recipient hash
    # @param hash_key [String] The recipient hash
    # @return [String, nil] The email address if found, nil otherwise
    def lookup_incoming_recipient(hash_key)
      incoming_recipient_lookup[hash_key]
    end

  end
end
```

#### File: `lib/onetime/initializers.rb` (MODIFY)

Add the incoming recipients initializer:

```ruby
# Near other initializer requires
require_relative 'initializers/setup_incoming_recipients'
```

#### File: `lib/onetime/initializers/boot.rb` (MODIFY)

Call the setup method during boot:

```ruby
# In the boot sequence, after other initializers
setup_incoming_recipients
```

### 8. Mail Views

#### File: `lib/onetime/mail/views/common.rb` (MODIFY)

Add the `IncomingSecretNotification` mail view class:

```ruby
# Add after the SecretLink class

class IncomingSecretNotification < Mail::Views::Base
  def init secret, recipient
    raise ArgumentError, "Secret required" unless secret
    raise ArgumentError, "Recipient required" unless recipient

    self[:secret] = secret
    self[:email_address] = recipient
    self[:from_name] = OT.conf[:emailer][:fromname]
    self[:from] = OT.conf[:emailer][:from]
    self[:signature_link] = baseuri

    # Get memo from metadata if available
    # Load metadata to access memo field
    metadata = V2::Metadata.load(secret.metadata_key) if secret.metadata_key
    self[:memo] = metadata&.memo
  end

  def subject
    # Security: Don't include memo in subject line as it's visible in email list views
    # The memo is still shown in the email body for context
    "You've received a secret message"
  end

  def display_domain
    secret_display_domain self[:secret]
  end

  def uri_path
    raise ArgumentError, "Invalid secret key" unless self[:secret]&.key
    secret_uri self[:secret]
  end
end
```

Also update the `SecretLink` class to use `baseuri` instead of hardcoded signature link:

```ruby
# In SecretLink class, change:
self[:signature_link] = 'https://onetimesecret.com/'
# To:
self[:signature_link] = baseuri
```

---

## Frontend Changes

### 1. Vue Components

#### File: `src/components/incoming/IncomingMemoInput.vue` (NEW)

```vue
<!-- src/components/incoming/IncomingMemoInput.vue -->

<script setup lang="ts">
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const props = withDefaults(
    defineProps<{
      modelValue: string;
      maxLength?: number;
      error?: string;
      disabled?: boolean;
      placeholder?: string;
    }>(),
    {
      maxLength: 50,
      disabled: false,
    }
  );

  const emit = defineEmits<{
    'update:modelValue': [value: string];
    blur: [];
  }>();

  const placeholderText = computed(() => props.placeholder || t('incoming.memo_placeholder'));
  const charCount = computed(() => props.modelValue.length);
  const isNearLimit = computed(() => charCount.value > props.maxLength * 0.8);
  const isAtLimit = computed(() => charCount.value >= props.maxLength);

  const statusColor = computed(() => {
    if (props.error) return 'border-red-500 focus:border-red-500 focus:ring-red-500';
    if (isAtLimit.value) return 'border-amber-500 focus:border-amber-500 focus:ring-amber-500';
    return 'border-gray-200 focus:border-blue-500 focus:ring-blue-500';
  });

  const counterColor = computed(() => {
    if (isAtLimit.value) return 'text-amber-600 dark:text-amber-400';
    if (isNearLimit.value) return 'text-gray-600 dark:text-gray-400';
    return 'text-gray-500 dark:text-gray-500';
  });

  const handleInput = (event: Event) => {
    const target = event.target as HTMLInputElement;
    emit('update:modelValue', target.value);
  };

  const handleBlur = () => {
    emit('blur');
  };
</script>

<template>
  <div class="w-full">
    <label
      for="incoming-memo"
      class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
      {{ t('incoming.memo_label') }}
      <span
        v-if="error"
        class="text-red-500">
        *
      </span>
    </label>

    <div class="relative">
      <input
        id="incoming-memo"
        type="text"
        :value="modelValue"
        :maxlength="maxLength"
        :disabled="disabled"
        :placeholder="placeholderText"
        :class="[
          statusColor,
          'block w-full rounded-lg border px-4 py-3 text-base text-gray-900',
          'transition-all duration-200',
          'placeholder:text-gray-400',
          'disabled:bg-gray-50 disabled:text-gray-500',
          'dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500',
          'dark:focus:ring-blue-400',
        ]"
        :aria-label="t('incoming.memo_placeholder')"
        :aria-invalid="!!error"
        :aria-describedby="error ? 'memo-error' : 'memo-counter'"
        @input="handleInput"
        @blur="handleBlur" />

      <div
        v-if="isNearLimit || error"
        class="mt-1 flex items-center justify-between">
        <span
          v-if="error"
          id="memo-error"
          class="text-sm text-red-600 dark:text-red-400">
          {{ error }}
        </span>
        <span
          v-if="isNearLimit"
          id="memo-counter"
          :class="[counterColor, 'ml-auto text-sm']">
          {{ charCount }} / {{ maxLength }}
        </span>
      </div>
    </div>

    <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
      <!-- {{ t('incoming.memo_hint') }} -->
    </p>
  </div>
</template>
```

#### File: `src/components/incoming/IncomingRecipientDropdown.vue` (NEW)

```vue
<!-- src/components/incoming/IncomingRecipientDropdown.vue -->

<script setup lang="ts">
  import { ref, computed } from 'vue';
  import { IncomingRecipient } from '@/schemas/api/incoming';
  import { useClickOutside } from '@/composables/useClickOutside';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const props = withDefaults(
    defineProps<{
      modelValue: string;
      recipients: IncomingRecipient[];
      error?: string;
      disabled?: boolean;
      placeholder?: string;
    }>(),
    {
      disabled: false,
      placeholder: 'Select a recipient',
    }
  );

  const emit = defineEmits<{
    'update:modelValue': [value: string];
    blur: [];
  }>();

  const isOpen = ref(false);
  const dropdownRef = ref<HTMLElement | null>(null);

  useClickOutside(dropdownRef, () => {
    isOpen.value = false;
  });

  const selectedRecipient = computed(() => {
    return props.recipients.find((r) => r.hash === props.modelValue);
  });

  const displayText = computed(() => {
    return selectedRecipient.value?.name || props.placeholder;
  });

  const statusColor = computed(() => {
    if (props.error) return 'border-red-500 focus:border-red-500 focus:ring-red-500';
    return 'border-gray-200 focus:border-blue-500 focus:ring-blue-500';
  });

  const toggleDropdown = () => {
    if (!props.disabled) {
      isOpen.value = !isOpen.value;
    }
  };

  const selectRecipient = (recipientId: string) => {
    emit('update:modelValue', recipientId);
    isOpen.value = false;
    emit('blur');
  };

  const handleKeydown = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      isOpen.value = false;
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      toggleDropdown();
    }
  };
</script>

<template>
  <div
    ref="dropdownRef"
    class="w-full">
    <label
      for="incoming-recipient"
      class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
      {{ t('incoming.recipient_label') }}
      <span
        v-if="error"
        class="text-red-500">
        *
      </span>
    </label>

    <div class="relative">
      <button
        id="incoming-recipient"
        type="button"
        :disabled="disabled"
        :class="[
          statusColor,
          'flex w-full items-center justify-between rounded-lg border px-4 py-3',
          'text-left text-base transition-all duration-200',
          'disabled:bg-gray-50 disabled:text-gray-500',
          'dark:bg-slate-800 dark:text-white',
          selectedRecipient ? 'text-gray-900 dark:text-white' : 'text-gray-400 dark:text-gray-500',
        ]"
        :aria-label="t('incoming.recipient_aria_label')"
        :aria-expanded="isOpen"
        :aria-invalid="!!error"
        :aria-describedby="error ? 'recipient-error' : undefined"
        @click="toggleDropdown"
        @keydown="handleKeydown">
        <span>{{ displayText }}</span>
        <svg
          :class="[
            'size-5 transition-transform duration-200',
            isOpen ? 'rotate-180' : '',
            'text-gray-400 dark:text-gray-500',
          ]"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      <!-- Dropdown Menu -->
      <div
        v-if="isOpen && recipients.length > 0"
        class="absolute z-10 mt-1 w-full rounded-lg border border-gray-200 bg-white shadow-lg dark:border-gray-700 dark:bg-slate-800">
        <ul
          class="max-h-60 overflow-auto py-1"
          role="listbox">
          <li
            v-for="recipient in recipients"
            :key="recipient.hash"
            role="option"
            :aria-selected="modelValue === recipient.hash"
            :class="[
              'cursor-pointer px-4 py-2 transition-colors duration-150',
              modelValue === recipient.hash
                ? 'bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300'
                : 'text-gray-900 hover:bg-gray-50 dark:text-white dark:hover:bg-slate-700',
            ]"
            @click="selectRecipient(recipient.hash)">
            <div class="flex items-center justify-between">
              <span class="font-medium">{{ recipient.name }}</span>
              <svg
                v-if="modelValue === recipient.hash"
                class="size-5 text-blue-600 dark:text-blue-400"
                fill="currentColor"
                viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                  clip-rule="evenodd" />
              </svg>
            </div>
          </li>
        </ul>
      </div>

      <!-- Empty State -->
      <div
        v-else-if="isOpen && recipients.length === 0"
        class="absolute z-10 mt-1 w-full rounded-lg border border-gray-200 bg-white p-4 text-center shadow-lg dark:border-gray-700 dark:bg-slate-800">
        <p class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('incoming.no_recipients_available') }}
        </p>
      </div>

      <!-- Error Message -->
      <span
        v-if="error"
        id="recipient-error"
        class="mt-1 block text-sm text-red-600 dark:text-red-400">
        {{ error }}
      </span>
    </div>

    <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
      <!-- {{ t('incoming.recipient_hint') }} -->
    </p>
  </div>
</template>
```

### 2. Vue Views

#### File: `src/views/incoming/IncomingSecretForm.vue` (NEW)

Create the complete form view as shown in the main branch. The file is too large to include in full here, but key points:

- Uses `useIncomingSecret` composable for form logic
- Includes `IncomingMemoInput`, `IncomingRecipientDropdown`, and `SecretContentInputArea` components
- Shows loading/error states
- Handles form submission and validation
- Provides reset functionality

See the full implementation in the main branch at `src/views/incoming/IncomingSecretForm.vue`.

#### File: `src/views/incoming/IncomingSuccessView.vue` (NEW)

Create the success view as shown in the main branch. Key features:

- Displays success message with reference ID
- Allows copying reference ID to clipboard
- Links to receipt page
- Provides "Send Another Secret" button

See the full implementation in the main branch at `src/views/incoming/IncomingSuccessView.vue`.

### 3. Composables

#### File: `src/composables/useIncomingSecret.ts` (NEW)

See the full implementation in the main branch. This composable handles:

- Form state management
- Validation logic
- API calls via the incoming store
- Navigation after success

### 4. Stores

#### File: `src/stores/incomingStore.ts` (NEW)

See the full implementation in the main branch. This store manages:

- Configuration loading from API
- Secret creation API calls
- State management for recipients and settings

### 5. Schemas

#### File: `src/schemas/api/incoming.ts` (NEW)

```typescript
// src/schemas/api/incoming.ts

import { z } from 'zod';

/**
 * Schema for incoming recipient configuration
 * Note: Uses hash instead of email to prevent exposing recipient addresses
 */
export const incomingRecipientSchema = z.object({
  hash: z.string().min(1),
  name: z.string(),
});

export type IncomingRecipient = z.infer<typeof incomingRecipientSchema>;

/**
 * Schema for incoming secrets configuration response from API
 */
export const incomingConfigSchema = z.object({
  enabled: z.boolean(),
  memo_max_length: z.number().int().positive().default(50),
  recipients: z.array(incomingRecipientSchema).default([]),
  default_ttl: z.number().int().positive().optional(),
});

export type IncomingConfig = z.infer<typeof incomingConfigSchema>;

/**
 * Schema for incoming secret creation payload
 * Simple payload - passphrase and ttl come from backend config
 * Memo is optional - only secret and recipient are required
 * Recipient is now a hash string instead of email for security
 * Note: Memo max length validation is enforced by backend config and UI component
 */
export const incomingSecretPayloadSchema = z.object({
  memo: z.string().optional().default(''),
  secret: z.string().min(1),
  recipient: z.string().min(1), // Now expects hash instead of email
});

export type IncomingSecretPayload = z.infer<typeof incomingSecretPayloadSchema>;

/**
 * Schema for metadata object in the response
 */
const metadataRecordSchema = z.object({
  identifier: z.string(),
  key: z.string(),
  custid: z.string(),
  state: z.string(),
  secret_shortkey: z.string(),
  shortkey: z.string(),
  memo: z.string().optional(),
  recipients: z.string().optional(),
});

/**
 * Schema for secret object in the response
 */
const secretRecordSchema = z.object({
  identifier: z.string(),
  key: z.string(),
  state: z.string(),
  shortkey: z.string(),
});

/**
 * Schema for incoming secret creation response
 * Matches the actual V2 API response format
 */
export const incomingSecretResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
  shrimp: z.string().optional(),
  custid: z.string().optional(),
  record: z.object({
    metadata: metadataRecordSchema,
    secret: secretRecordSchema,
  }),
  details: z.object({
    memo: z.string(),
    recipient: z.string(),
  }).optional(),
});

export type IncomingSecretResponse = z.infer<typeof incomingSecretResponseSchema>;
```

### 6. Router

#### File: `src/router/incoming.routes.ts` (NEW)

```typescript
// src/router/incoming.routes.ts

import QuietFooter from '@/components/layout/QuietFooter.vue';
import QuietHeader from '@/components/layout/QuietHeader.vue';
import type { RouteRecordRaw } from 'vue-router';

const incomingRoutes: RouteRecordRaw[] = [
  {
    path: '/incoming',
    name: 'IncomingSecretForm',
    components: {
      default: () => import('@/views/incoming/IncomingSecretForm.vue'),
      header: QuietHeader,
      footer: QuietFooter,
    },
    meta: {
      requiresAuth: false,
      title: 'Send a Secret',
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: false,
        displayToggles: true,
      },
    },
  },
  {
    path: '/incoming/:metadataKey',
    name: 'IncomingSuccess',
    components: {
      default: () => import('@/views/incoming/IncomingSuccessView.vue'),
      header: QuietHeader,
      footer: QuietFooter,
    },
    meta: {
      requiresAuth: false,
      title: 'Secret Sent Successfully',
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: false,
        displayToggles: true,
      },
    },
  },
];

export default incomingRoutes;
```

#### File: `src/router/index.ts` (MODIFY)

Import and add the incoming routes:

```typescript
import incomingRoutes from './incoming.routes';

// In the routes array, add:
...incomingRoutes,
```

### 7. Locales

#### File: `src/locales/en.json` (MODIFY)

Add the incoming secrets translations. The structure should be:

```json
{
  "incoming": {
    "page_title": "Send a Secret",
    "page_description": "Share sensitive information securely with our support team",
    "loading_config": "Loading...",
    "config_error_title": "Failed to load configuration",
    "feature_disabled_title": "Feature Not Available",
    "feature_disabled_description": "This feature is currently disabled. Please contact support for assistance.",
    "memo_label": "Memo",
    "memo_placeholder": "Brief description (e.g., Password reset request)",
    "memo_hint": "Help us route your message to the right person",
    "recipient_label": "Send to",
    "recipient_placeholder": "Select a recipient",
    "recipient_aria_label": "Select a recipient for this secret",
    "recipient_hint": "Choose who will receive this secure message",
    "no_recipients_available": "No recipients are available",
    "secret_content_label": "Secret Information",
    "secret_content_placeholder": "Paste sensitive information here (passwords, keys, etc.)",
    "secret_content_hint": "This information will be encrypted and only viewable once",
    "submit_button": "Send Secret",
    "submit_secret": "Send Secret",
    "submitting_button": "Sending...",
    "submitting": "Sending...",
    "reset_button": "Clear Form",
    "reset_form": "Clear Form",
    "success_title": "Sent Successfully",
    "success_description": "Your secure message has been delivered.",
    "reference_id": "Reference ID",
    "success_info_title": "What happens next?",
    "success_info_description": "The recipient will be able to view this secret only once. After they view it, the secret will be permanently deleted.",
    "create_another": "Send Another Secret",
    "tagline1": "Share sensitive information securely",
    "tagline2": "Keep passwords and private data out of email and chat logs",
    "end_of_experience_suggestion": "Save your <a href='{receiptUrl}'>receipt</a> for your records."
  }
}
```

**IMPORTANT:** Remove any old/deprecated incoming translations that may exist under different paths (e.g., under `web.incoming`).

---

## Configuration Changes

### File: `etc/config.example.yaml` (MODIFY)

Update the incoming secrets configuration section:

```yaml
:features:
  # Incoming Secrets - Allows anonymous users to send secrets to pre-configured recipients
  # IMPORTANT: Requires email configuration (:emailer section) to send notifications
  :incoming:
    :enabled: false
    # Maximum length for the optional memo field (subject line in email)
    :memo_max_length: 50
    # Optional passphrase applied to all incoming secrets (nil = no passphrase)
    :default_passphrase: null
    # Default TTL in seconds (604800 = 7 days)
    :default_ttl: 604800
    # Recipients who can receive incoming secrets
    # Format: Can be configured via ENV vars: INCOMING_RECIPIENT_N=email,name
    # Email addresses are hashed at startup and never exposed in API responses
    # Examples:
    #   INCOMING_RECIPIENT_1=support@example.com,Support Team
    #   INCOMING_RECIPIENT_2=security@example.com,Security Team
    #   INCOMING_RECIPIENT_3=admin@example.com  (name defaults to 'admin')
    :recipients:
      - :email: 'support@example.com'
        :name: 'Support Team'
      - :email: 'security@example.com'
        :name: 'Security Team'
```

### File: `etc/config.schema.yaml` (MODIFY)

Add schema validation for the incoming configuration:

```yaml
# Add to the features section:
:features:
  :incoming: include(':incoming', required=False)

# Add the incoming schema definition:
:incoming:
  :enabled: any(bool(), str())
  :memo_max_length: any(int(), str())
  :default_passphrase: any(str(), required=False)
  :default_ttl: any(int(), str())
  :recipients: list(include(':incoming_recipient'))

:incoming_recipient:
  :email: str()
  :name: str()
```

---

## Email Templates

### File: `templates/mail/incoming_secret_notification.html` (NEW)

**Note:** This template is minified HTML. It should be created as a single-line template.

```html
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd"><html xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office"><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8" /><meta name="viewport" content="width=device-width, initial-scale=1" /><meta http-equiv="X-UA-Compatible" content="IE=edge" /><meta name="format-detection" content="date=no" /><meta name="format-detection" content="telephone=no" /><title>OnetimeSecret.com</title><style type="text/css">body{ margin: 0; padding: 0; -ms-text-size-adjust: 100%; -webkit-text-size-adjust: 100%;} table{ border-spacing: 0;} table td{ border-collapse: collapse;} .ExternalClass{ width: 100%;} .ExternalClass, .ExternalClass p, .ExternalClass span, .ExternalClass font, .ExternalClass td, .ExternalClass div{ line-height: 100%;} .ReadMsgBody{ width: 100%; background-color: #ebebeb;} table{ mso-table-lspace: 0pt; mso-table-rspace: 0pt;} img{ -ms-interpolation-mode: bicubic;} .yshortcuts a{ border-bottom: none !important;} @media screen and (max-width: 599px){ .force-row, .container{ width: 100% !important; max-width: 100% !important;}} @media screen and (max-width: 400px){ .container-padding{ padding-left: 12px !important; padding-right: 12px !important;}} .ios-footer a{ color: #aaaaaa !important; text-decoration: underline;} a[href^="x-apple-data-detectors:"], a[x-apple-data-detectors]{ color: inherit !important; text-decoration: none !important; font-size: inherit !important; font-family: inherit !important; font-weight: inherit !important; line-height: inherit !important;} </style></head><body style="margin: 0; padding: 0" bgcolor="#ffffff" leftmargin="0" topmargin="0" marginwidth="0" marginheight="0"><table border="0" width="100%" height="100%" cellpadding="0" cellspacing="0" bgcolor="#ffffff"><tr><td align="center" valign="top" bgcolor="#ffffff" style="background-color: #ffffff"><br /><table border="0" width="600" cellpadding="0" cellspacing="0" class="container" style="width: 600px; max-width: 600px"><tr><td class="container-padding header" align="left" style=" font-family: Helvetica, Arial, sans-serif; text-align: center; "><br /></td></tr><tr><td class="container-padding content" align="left" style=" padding-left: 24px; padding-right: 24px; padding-top: 12px; padding-bottom: 12px; background-color: #ffffff; "><img alt="Onetime Secret" src="https://onetimesecret.com/v3/img/onetime-logo-v3-xl.svg" style=" border: 0; display: block; outline: 0; margin: 0 auto 42px 0; padding: 0; text-decoration: none; height: 48px; width: 48px; font-size: 0px; text-align: center; background-color: #dc4a22; " width="48px" height="48px" /><div class="title" style=" font-family: Helvetica, Arial, sans-serif; font-size: 18px; color: #374550; "><p>You've received a secure message:</p></div>{{#memo}}<div class="memo" style=" font-family: Helvetica, Arial, sans-serif; font-size: 16px; font-weight: bold; padding: 12px; background-color: #f5f5f5; border-left: 4px solid #dc4a22; margin: 12px 0; color: #333333; "><p>Memo: {{ memo }}</p></div>{{/memo}}<div class="body-text" style=" font-family: Helvetica, Arial, sans-serif; font-size: 14px; line-height: 20px; text-align: left; color: #333333; "><p>Someone has sent you a secure message through {{ display_domain }}.</p><p>To view this secret, click the link below:</p><div style=" font-family: Helvetica, Arial, sans-serif; font-size: 24px; font-weight: bold; line-height: 36px; text-align: left; margin: 20px 0; "><a href="{{ display_domain }}{{ uri_path }}" style="color: #dc4a22; word-break: break-all;" rel="noopener noreferrer" ><span style="display: block;">{{ display_domain }}</span><span>{{ uri_path }}</span></a ></div><p style=" background-color: #fff9e6; border-left: 4px solid #ffa500; padding: 12px; margin: 20px 0; "><strong>Important:</strong> This link will only work once. After viewing, the secret will be permanently deleted.</p><br /><p style="font-size: 12px; color: #666;"><i>This message was sent via <a href="{{ signature_link }}" rel="noopener noreferrer" style="color: #dc4a22;">Onetime Secret</a></i></p></div></td></tr></table></td></tr></table></body></html>
```

### Additional Email Template Updates

**Note:** All existing email templates were updated to use the SVG logo instead of PNG.

Changed from: `onetime-logo-v3-sm.png`
Changed to: `onetime-logo-v3-xl.svg`

The following templates should be updated if they exist in your develop branch:
- `templates/mail/feedback_email.html`
- `templates/mail/password_request.html`
- `templates/mail/secret_link.html`
- `templates/mail/test_email.html`
- `templates/mail/welcome.html`

---

## Tests

### 1. Ruby Backend Tests

#### File: `tests/unit/ruby/try/60_logic/60_incoming/01_get_config_try.rb` (NEW)

Create tests for the GetConfig logic class following the existing try test patterns in the codebase.

#### File: `tests/unit/ruby/try/60_logic/60_incoming/02_validate_recipient_try.rb` (NEW)

Create tests for the ValidateRecipient logic class.

#### File: `tests/unit/ruby/try/60_logic/60_incoming/03_create_incoming_secret_try.rb` (NEW)

Create tests for the CreateIncomingSecret logic class.

#### File: `tests/unit/ruby/try/80_incoming/01_incoming_feature_integration_try.rb` (NEW)

Create integration tests for the complete incoming secrets feature.

### 2. Vue/TypeScript Tests

#### File: `tests/unit/vue/stores/incomingStore.spec.ts` (NEW)

Create comprehensive tests for the incoming store covering:
- Configuration loading
- Secret creation
- Error handling
- State management

#### File: `tests/integration/web/incoming-secret-flow.spec.ts` (NEW)

Create end-to-end tests for the incoming secrets user flow.

---

## Infrastructure Fixes

### 1. OpenSSL CRL Fix

#### File: `lib/onetime/initializers/setup_diagnostics.rb` (MODIFY)

**Context:** OpenSSL 3.6+ enables strict CRL checking by default, but macOS's OpenSSL build lacks a CRL bundle, causing valid certificates to fail. This fix disables CRL checking while maintaining certificate verification.

**Note:** The specific fix implementation may vary based on OpenSSL version. The approach in main was:

```ruby
# At the top, add:
require 'openssl'

# In the setup_diagnostics method:
# Fix for OpenSSL 3.6+ CRL verification failures on macOS
OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_mode] = OpenSSL::SSL::VERIFY_PEER

# Note: The verify_flags approach was commented out due to version incompatibility
# OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_flags] &=
#   ~(OpenSSL::X509::V_FLAG_CRL_CHECK_ALL | OpenSSL::X509::V_FLAG_CRL_CHECK)
```

### 2. AWS SES Mailer Fix

#### File: `lib/onetime/mail/mailer/ses_mailer.rb` (MODIFY)

**Changes needed:**

1. **Reply-to fix:** Only include `reply_to_addresses` if reply_to is present:

```ruby
# In the send_email method, change:
email_params = {
  # ... other params ...
  reply_to_addresses: [reply_to],
}

# To:
email_params = {
  # ... other params ...
}

# Only include reply_to_addresses if reply_to is present
if reply_to && !reply_to.to_s.empty?
  email_params[:reply_to_addresses] = [reply_to]
end
```

2. **OpenSSL fix for SES client:**

```ruby
def self.setup
  # Configure AWS SES client with OpenSSL 3.6+ CRL fix
  # OpenSSL 3.6 enables strict CRL checking by default, but macOS's
  # OpenSSL build lacks a CRL bundle, causing valid certificates to fail.
  # We create a custom X509::Store with CRL checking disabled.
  # See: https://github.com/rails/rails/issues/55886

  # Create custom certificate store with system certs but no CRL checking
  cert_store = OpenSSL::X509::Store.new
  cert_store.set_default_paths

  @ses_client = Aws::SESV2::Client.new(
    region: OT.conf[:emailer][:region] || raise("Region not configured"),
    credentials: Aws::Credentials.new(
      OT.conf[:emailer][:user],
      OT.conf[:emailer][:pass],
    ),
    ssl_verify_peer: true,
    ssl_ca_store: cert_store,
  )
end
```

---

## Implementation Checklist

### Backend

- [ ] Create `apps/api/v2/controllers/incoming.rb`
- [ ] Add incoming controller to `apps/api/v2/controllers.rb`
- [ ] Create `apps/api/v2/logic/incoming.rb`
- [ ] Create `apps/api/v2/logic/incoming/get_config.rb`
- [ ] Create `apps/api/v2/logic/incoming/validate_recipient.rb`
- [ ] Create `apps/api/v2/logic/incoming/create_incoming_secret.rb`
- [ ] Add API routes to `apps/api/v2/routes`
- [ ] Add web routes to `apps/web/core/routes`
- [ ] Add `memo` field to `apps/api/v2/models/metadata.rb`
- [ ] Add incoming features defaults to `lib/onetime/config.rb`
- [ ] Create `lib/onetime/initializers/setup_incoming_recipients.rb`
- [ ] Add initializer to `lib/onetime/initializers.rb`
- [ ] Call setup in `lib/onetime/initializers/boot.rb`
- [ ] Add `IncomingSecretNotification` class to `lib/onetime/mail/views/common.rb`
- [ ] Update `SecretLink` signature_link to use `baseuri` (if not already done)

### Frontend

- [ ] Create `src/components/incoming/IncomingMemoInput.vue`
- [ ] Create `src/components/incoming/IncomingRecipientDropdown.vue`
- [ ] Create `src/views/incoming/IncomingSecretForm.vue`
- [ ] Create `src/views/incoming/IncomingSuccessView.vue`
- [ ] Create `src/composables/useIncomingSecret.ts`
- [ ] Create `src/stores/incomingStore.ts`
- [ ] Create `src/schemas/api/incoming.ts`
- [ ] Create `src/router/incoming.routes.ts`
- [ ] Add routes to `src/router/index.ts`
- [ ] Add translations to `src/locales/en.json`
- [ ] Remove any deprecated incoming translations

### Configuration

- [ ] Update `etc/config.example.yaml` with new incoming configuration
- [ ] Update `etc/config.schema.yaml` with incoming schema

### Email Templates

- [ ] Create `templates/mail/incoming_secret_notification.html`
- [ ] Update email templates to use SVG logo (feedback, password_request, secret_link, test, welcome)

### Infrastructure Fixes

- [ ] Apply OpenSSL CRL fix to `lib/onetime/initializers/setup_diagnostics.rb`
- [ ] Apply AWS SES fixes to `lib/onetime/mail/mailer/ses_mailer.rb`

### Tests

- [ ] Create `tests/unit/ruby/try/60_logic/60_incoming/01_get_config_try.rb`
- [ ] Create `tests/unit/ruby/try/60_logic/60_incoming/02_validate_recipient_try.rb`
- [ ] Create `tests/unit/ruby/try/60_logic/60_incoming/03_create_incoming_secret_try.rb`
- [ ] Create `tests/unit/ruby/try/80_incoming/01_incoming_feature_integration_try.rb`
- [ ] Create `tests/unit/vue/stores/incomingStore.spec.ts`
- [ ] Create `tests/integration/web/incoming-secret-flow.spec.ts`

### Verification

- [ ] Test configuration loading endpoint
- [ ] Test recipient validation endpoint
- [ ] Test secret creation flow
- [ ] Test email notification delivery
- [ ] Test error handling and edge cases
- [ ] Verify recipient email hashing works correctly
- [ ] Verify OpenSSL and AWS SES fixes resolve connection issues

---

## Important Notes

### Security Considerations

1. **Email Hashing:** Recipient emails are never exposed in API responses. They are hashed using SHA256 with the site secret as salt.

2. **Rate Limiting:** The feature includes rate limiting for:
   - `get_page` - Loading configuration
   - `create_secret` - Creating secrets
   - `email_recipient` - Sending emails

3. **Validation:** All inputs are validated both client-side and server-side.

### Design Patterns

1. **V2 API Pattern:** The implementation follows the existing V2 API pattern with Logic classes handling business logic.

2. **Vue Composition API:** All frontend components use the Vue 3 Composition API with `<script setup>`.

3. **Pinia Store:** State management follows the existing Pinia store patterns.

4. **Zod Schemas:** All API responses are validated using Zod schemas.

### Adaptation Notes

The user mentioned that locale files are structured differently between branches. However, analysis shows both branches use the same structure (single JSON files). If your develop branch has a different structure (e.g., split locale files), adapt the locale changes accordingly.

The `Secret` model appears identical in both branches - no `encrypted` field exists in either. If your develop branch has different model fields, adapt the `create_and_encrypt_secret` method in `CreateIncomingSecret` accordingly.

---

## Questions or Issues

If you encounter any discrepancies or need clarification on any part of this migration:

1. Check the original PR #2016 for additional context
2. Review the commit history for detailed change descriptions
3. Test each component incrementally to isolate issues
4. Ensure all dependencies (gems, npm packages) are up to date

---

**End of Migration Guide**
