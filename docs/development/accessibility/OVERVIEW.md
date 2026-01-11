# Accessibility Overview

## Introduction

Onetime Secret is a privacy tool that helps you securely share sensitive information like passwords or private messages. The key principle is simple: when someone shares a secret, it can be viewed exactly once before being instantly and permanently deleted. This prevents sensitive data from lingering in email, chat logs, or other communication systems.

The service is available in two forms. First, there's the free and open-source project that anyone can use at onetimesecret.com or install on their own servers. The project follows an open-source first development model, meaning new features are built for and tested in the open-source version before being added to paid services. This ensures that core privacy functionality remains accessible to everyone.

Some organizations choose to use the paid service, which allows them to add their own branding and custom web addresses for sharing secrets. For example, a company's IT help desk might send password reset links that come from secretlink.company.com instead of onetimesecret.com. This helps recipients trust that the links are legitimate since they come from their organization's own domain.

Whether you're using the open-source version or a branded instance, the core experience remains straightforward:
- Click the secret link to view the content
- Enter the passphrase if one was set by the sender
- View the secret, which is then permanently deleted

For those who want to create and share secrets, the interface is designed to be simple and usable without requiring an account. You can enter your secret text, optionally set a passphrase and expiration time, and then share the generated link with your recipient. The service also provides features for more advanced users, like an API for automation, while maintaining its focus on being accessible to everyone who needs to share sensitive information securely.

## Accessibility Features

Onetime Secret focuses on two primary workflows: creating/sharing secrets and receiving secrets. Our accessibility work ensures these core functions are usable by everyone, regardless of how they interact with the platform.

### Recipient Experience

We'll start with the recipient experience. All users benefit from a positive experience when receiving and viewing secrets.

The secret viewing interface incorporates accessibility features to ensure that receiving and viewing secrets is straightforward for all users. Here's how we've enhanced the experience:

#### Semantic HTML Structure
- **Landmarks:** Added `main`, `nav`, and `footer` landmarks to define the structure of the page
- **Heading Levels:** Utilized appropriate heading hierarchies (H1-H6) for clear content organization
- **Role Attributes:** Incorporated necessary `role` attributes to improve document semantics and assistive technology navigation

#### Focus and Keyboard Navigation
- **Descriptive Labels:** Implemented descriptive `aria-label` attributes for interactive elements to provide clear context
- **Live Regions:** Employed `aria-live` regions to announce dynamic content updates to screen readers
- **Toggle States:** Added `aria-pressed` states for toggle buttons to indicate their current status
- **Decorative Elements:** Applied `aria-hidden="true"` to non-essential decorative elements to streamline screen reader output
- **Enhanced Focus Styles:** Improved focus indicators for all interactive elements to ensure visibility
- **Contrast:** Ensured focus indicators maintain sufficient contrast across all color schemes
- **Focus Rings:** Added focus rings with adequate contrast to assist keyboard navigation

#### Screen Reader Support
- **Form Field Labeling and Descriptive Text:** Improved labeling and descriptions for all interactive elements
- **Status Announcements and Dynamic Updates:** Implemented `aria-live` regions to keep users informed of changes and actions

#### Visual Accessibility
- **Dark Mode:** Enhanced text contrast in dark mode to improve readability
- **Alert Messages:** Increased contrast for alert messages to ensure they stand out
- **Brand Colors:** Adjusted brand colors to achieve better visibility and accessibility
- **Disabled States:** Increased opacity of disabled states to clearly distinguish non-interactive elements

### Secret Creation and Management Experience

We've implemented fundamental accessibility features and continue to improve the experience:
- Basic keyboard navigation through all form controls
- Clear error messages that work with screen readers
- Light and dark mode support
- Simple, linear workflow that's easy to follow

### Testing and Feedback

While these testing initiatives are in development, we welcome community contributions through discussions and pull requests:
- Utilizing automated accessibility checkers
- Planning manual testing with popular screen readers (NVDA, VoiceOver, JAWS)
- Implementing keyboard-only navigation testing
- Engaging with users who rely on assistive technologies

#### Reporting Accessibility Issues
To report accessibility issues or suggest improvements, you can:

1. Open an issue on our GitHub repository
2. Use the feedback form in the application footer
3. Contact our support team through the website

## Final Thoughts

Secure communication should be accessible to everyone. Onetime Secret implements accessibility features following established standards and best practices, focusing on core functionality that lets all users share and receive secrets effectively. We welcome feedback from users to help identify areas where we can improve the platform's accessibility.

Best regards,
Delano
