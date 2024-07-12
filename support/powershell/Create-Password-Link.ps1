

<#
.SYNOPSIS
This demo script simulates generating a strong password and creates a one-time secret using the OneTimeSecret service. (Passwords are actually randomly selected from a pre-defined list.)

NOTE: Not meant for production use.

.DESCRIPTION
The script performs the following actions:
1. Sets up environment variables for the OneTimeSecret service.
2. Configures TLS 1.2 for secure communication.
3. Imports the OneTimeSecret module.
4. Defines a function that selects a random password from a pre-defined list. This mimics the output expected from System.Web.Security.Membership.GeneratePassword() (which is not available on macos Powershell).
5. Sets the authorization token for OneTimeSecret.
6. Generates a strong password.
7. Creates a new one-time secret with the generated password.

.NOTES
Prerequisites:
- PowerShell 7.0 or later (for null-coalescing operator)
- OneTimeSecret module must be installed
- System.Web assembly for password generation

Environment Variables:
BASE_URL: The base URL for the OneTimeSecret service (default: "http://localhost:7143/")
OTS_USER_EMAIL: User email for OneTimeSecret authentication
OTS_API_KEY: API key for OneTimeSecret authentication

.EXAMPLE
To run the script:
1. Set the required environment variables:
   $env:BASE_URL = "http://localhost:7143/"
   $env:OTS_USER_EMAIL = "your_email@example.com"
   $env:OTS_API_KEY = "your_api_key"
2. Run the script:
   .\script_name.ps1

.LINK
https://github.com/chelnak/OneTimeSecret
#>

# Rest of your script content follows...

$BaseUrl = $env:BASE_URL ?? "http://localhost:7143/"
$UserEmail = $env:OTS_USER_EMAIL
$APIKey = $env:OTS_API_KEY

# SET TLS LEVEL
# Ensure we're using TLS 1.2 for secure communication
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Import the OneTimeSecret module for OTP functionality
Import-Module OneTimeSecret

# Add System.Web assembly for password generation
Add-Type -AssemblyName System.Web

# Function to Generate Strong Password
Function GenerateStrongPassword ([Parameter(Mandatory=$true)][int]$PasswordLenght)
{
    Add-Type -AssemblyName System.Web
    $PassComplexCheck = $false
    do {

        # Generate a random password
        #
        # $newPassword=[System.Web.Security.Membership]::GeneratePassword($PasswordLenght,1)
        #
        # If you are using a `*nix` platform (Mac or Linux) you will
        # see the error `Unable to find type [System.Web.Security.Membership]`
        # because the `System.Web.Security.Membership` module is not part of
        # PS Core on `*nix` platforms. You can overcome this by providing
        # a password using this argument:
        #
        # `-adminPassword $(ConvertTo-SecureString -AsPlainText
        # -Force '<Some Password Here>')`
        #
        # https://github.com/microsoft/OpenHack-FHIR/pull/11/files
        #
        # List of predefined passwords (see GeneratePassword.rb)
        $predefinedPasswordsWithSpecial = @(
            'z%!8UP', # ok
            '>%nYF8', '/b37U', 'g3H{l',
            '8%g)5T', # ok
            'm%vB6[',
            'I%4}?w', # too few arguments
            '8%!_eJ', # ok
            'Abcd%', 'D%efg', 'Tr+5n', 'w+9UG',
            'V9r@R', # malformed format string - %R
            'M&w8x'
        )
        $predefinedPasswordsOnlyBroken = @(
            'z%!8UP%R',
            'I%4}?w', # too few arguments
            'V9r@R' # malformed format string - %R
        )
         List of predefined passwords without special characters
        $predefinedPasswordsWithoutSpecial = @(
            'Tr5nw9UG', 'z8UPnYF8', 'b37Ug3Hl',
            '8g5TmvB6', 'I4wJ8eJ', 'V9rRM8wx'
        )

        # Randomly select a password from the list
        $newPassword = Get-Random -InputObject $predefinedPasswordsWithSpecial

        # Check if the password meets complexity requirements
        If (($newPassword -cmatch "[A-Z\p{Lu}\s]") `
            -and ($newPassword -cmatch "[a-z\p{Ll}\s]") `
            -and ($newPassword -match "[\d]") `
            -and ($newPassword -match "[^\w]")
        )
        {
            $PassComplexCheck=$True
        }

        # Explanation:
        #
        # Checks if the generated password meets requirements:
        #
        # 1. ($newPassword -cmatch "[A-Z\p{Lu}\s]")
        #    - Checks for at least one uppercase letter
        #    - [A-Z] matches any uppercase ASCII letter
        #    - \p{Lu} matches any Unicode uppercase letter
        #    - \s matches any whitespace character (though this might not be desirable in a password)
        #
        # 2. ($newPassword -cmatch "[a-z\p{Ll}\s]")
        #    - Checks for at least one lowercase letter
        #    - [a-z] matches any lowercase ASCII letter
        #    - \p{Ll} matches any Unicode lowercase letter
        #    - \s matches any whitespace character (again, might not be desirable)
        #
        # 3. ($newPassword -match "[\d]")
        #    - Checks for at least one digit
        #    - [\d] is equivalent to [0-9]
        #
        # 4. ($newPassword -match "[^\w]")
        #    - Checks for at least one non-word character (special character)
        #    - [^\w] matches any character that is not a word character
        #    - Word characters include A-Z, a-z, 0-9, and underscore (_)
        #    - So this checks for characters like @, #, $, %, etc.
        #
        # If all these conditions are met, $PassComplexCheck is set to True,
        # indicating that the password meets the required complexity standards.

    } While ($PassComplexCheck -eq $false)

    return $newPassword
} #end function

Write-Host "Setting Set-OTSAuthorizationToken"

# Set the authorization token for OneTimeSecret
# https://github.com/chelnak/OneTimeSecret/blob/master/src/Functions/Public/Set-OTSAuthorizationToken.ps1
Set-OTSAuthorizationToken -Username $ -APIKey $APIKey -BaseUrl $BaseUrl

Write-Host "Generating a strong password"

# Set New Complex Password
# Generate a new 14-character strong password
$MyPassword = GenerateStrongPassword(14)

Write-Host $MyPassword  # Display the generated password

Write-Host "Generating OTP Link"

# Create a new OTS shared secret with the generated password
# TTL (Time To Live) is set to 3600 seconds (1 hour)
$MySecret = New-OTSSharedSecret -Secret $MyPassword -Ttl 3200

Write-Host $MySecret  # Display the created secret details
