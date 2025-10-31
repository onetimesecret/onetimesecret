#!/bin/bash
# Manual test script for active sessions endpoints
#
# Usage:
#   1. Start the server: AUTHENTICATION_MODE=advanced bin/ots server
#   2. Run this script: bash docs/testing/manual-test-active-sessions.sh
#
# This script tests the three active sessions endpoints:
#   - GET /auth/active-sessions
#   - DELETE /auth/active-sessions/:id
#   - POST /auth/remove-all-active-sessions

BASE_URL="${BASE_URL:-http://localhost:7143}"
EMAIL="test-sessions-$(date +%s)@example.com"
PASSWORD="TestPassword123!"

echo "=== Active Sessions Manual Test ==="
echo "Base URL: $BASE_URL"
echo "Test Email: $EMAIL"
echo

# Create account
echo "1. Creating test account..."
CREATE_RESPONSE=$(curl -s -c cookies.txt -X POST "$BASE_URL/auth/create-account" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"login\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"password-confirm\":\"$PASSWORD\"}")
echo "Response: $CREATE_RESPONSE"
echo

# Login
echo "2. Logging in..."
LOGIN_RESPONSE=$(curl -s -b cookies.txt -c cookies.txt -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"login\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "Response: $LOGIN_RESPONSE"
echo

# Get account info (should include active_sessions_count)
echo "3. Getting account info..."
ACCOUNT_INFO=$(curl -s -b cookies.txt "$BASE_URL/auth/account" \
  -H "Accept: application/json")
echo "Response: $ACCOUNT_INFO"
echo

# List active sessions
echo "4. Listing active sessions..."
SESSIONS_RESPONSE=$(curl -s -b cookies.txt "$BASE_URL/auth/active-sessions" \
  -H "Accept: application/json")
echo "Response: $SESSIONS_RESPONSE"
echo

# Try to delete current session (should fail)
echo "5. Attempting to delete current session (should fail)..."
CURRENT_SESSION_ID=$(echo "$SESSIONS_RESPONSE" | grep -o '"id":"[^"]*","created_at"' | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Current session ID: $CURRENT_SESSION_ID"
DELETE_CURRENT=$(curl -s -b cookies.txt -X DELETE "$BASE_URL/auth/active-sessions/$CURRENT_SESSION_ID" \
  -H "Accept: application/json")
echo "Response: $DELETE_CURRENT"
echo

# Remove all other sessions
echo "6. Removing all other sessions..."
REMOVE_ALL=$(curl -s -b cookies.txt -X POST "$BASE_URL/auth/remove-all-active-sessions" \
  -H "Accept: application/json")
echo "Response: $REMOVE_ALL"
echo

# Verify only one session remains
echo "7. Verifying only current session remains..."
FINAL_SESSIONS=$(curl -s -b cookies.txt "$BASE_URL/auth/active-sessions" \
  -H "Accept: application/json")
echo "Response: $FINAL_SESSIONS"
echo

# Cleanup
echo "8. Cleaning up..."
curl -s -b cookies.txt -X POST "$BASE_URL/auth/logout" -H "Accept: application/json" > /dev/null
rm -f cookies.txt
echo "Done!"
