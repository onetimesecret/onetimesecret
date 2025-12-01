/**
 * File move definitions for Interaction Modes migration.
 * Based on docs/product/tasks/interaction-modes-migration-manifest.md
 */

export type MoveAction = 'move' | 'rename' | 'copy' | 'delete';

export interface FileMove {
  from: string;
  to: string | null;
  action: MoveAction;
  notes?: string;
}

export function fileMoves(): FileMove[] {
  return [
    // ========================================================================
    // Secret App: Conceal
    // ========================================================================
    {
      from: 'views/HomepageContainer.vue',
      to: 'apps/secret/conceal/Homepage.vue',
      action: 'move',
      notes: 'Refactor to use useSecretContext',
    },
    {
      from: 'views/Homepage.vue',
      to: null,
      action: 'delete',
      notes: 'Merged into Homepage.vue',
    },
    {
      from: 'views/BrandedHomepage.vue',
      to: 'apps/secret/conceal/BrandedHomepage.vue',
      action: 'move',
      notes: 'Keep for container import until refactored',
    },
    {
      from: 'views/DisabledHomepage.vue',
      to: 'apps/secret/conceal/AccessDenied.vue',
      action: 'rename',
    },
    {
      from: 'views/DisabledUI.vue',
      to: 'apps/secret/conceal/DisabledUI.vue',
      action: 'move',
    },
    {
      from: 'views/incoming/IncomingSecretForm.vue',
      to: 'apps/secret/conceal/IncomingForm.vue',
      action: 'rename',
    },
    {
      from: 'views/incoming/IncomingSuccessView.vue',
      to: 'apps/secret/conceal/IncomingSuccess.vue',
      action: 'rename',
    },

    // ========================================================================
    // Secret App: Reveal
    // ========================================================================
    {
      from: 'views/secrets/ShowSecretContainer.vue',
      to: 'apps/secret/reveal/ShowSecret.vue',
      action: 'move',
      notes: 'Refactor to merge branded/canonical',
    },
    {
      from: 'views/secrets/branded/ShowSecret.vue',
      to: 'apps/secret/reveal/branded/ShowSecret.vue',
      action: 'move',
      notes: 'Keep for container import until refactored',
    },
    {
      from: 'views/secrets/canonical/ShowSecret.vue',
      to: 'apps/secret/reveal/canonical/ShowSecret.vue',
      action: 'move',
      notes: 'Keep for container import until refactored',
    },
    {
      from: 'views/secrets/branded/UnknownSecret.vue',
      to: 'apps/secret/reveal/branded/UnknownSecret.vue',
      action: 'move',
      notes: 'Keep for container import until refactored',
    },
    {
      from: 'views/secrets/canonical/UnknownSecret.vue',
      to: 'apps/secret/reveal/UnknownSecret.vue',
      action: 'move',
      notes: 'Refactor to unify',
    },
    {
      from: 'views/secrets/ShowMetadata.vue',
      to: 'apps/secret/reveal/ShowMetadata.vue',
      action: 'move',
    },
    {
      from: 'views/secrets/UnknownMetadata.vue',
      to: 'apps/secret/reveal/UnknownMetadata.vue',
      action: 'move',
    },
    {
      from: 'views/secrets/BurnSecret.vue',
      to: 'apps/secret/reveal/BurnSecret.vue',
      action: 'move',
    },

    // ========================================================================
    // Secret App: Support
    // ========================================================================
    {
      from: 'views/Feedback.vue',
      to: 'apps/secret/support/Feedback.vue',
      action: 'move',
    },

    // ========================================================================
    // Secret App: Components (flat files in components/secrets/)
    // ========================================================================
    {
      from: 'components/secrets/HomepageLinksPlaceholder.vue',
      to: 'apps/secret/components/HomepageLinksPlaceholder.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/RecentSecretsTable.vue',
      to: 'apps/secret/components/RecentSecretsTable.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/SecretDisplayHelpContent.vue',
      to: 'apps/secret/components/SecretDisplayHelpContent.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/SecretLinkLine.vue',
      to: 'apps/secret/components/SecretLinkLine.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/SecretLinksTable.vue',
      to: 'apps/secret/components/SecretLinksTable.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/SecretLinksTableRow.vue',
      to: 'apps/secret/components/SecretLinksTableRow.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/SecretLinksTableRowActions.vue',
      to: 'apps/secret/components/SecretLinksTableRowActions.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/SecretMetadataTable.vue',
      to: 'apps/secret/components/SecretMetadataTable.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/SecretMetadataTableItem.vue',
      to: 'apps/secret/components/SecretMetadataTableItem.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/SecretRecipientHelpContent.vue',
      to: 'apps/secret/components/SecretRecipientHelpContent.vue',
      action: 'move',
    },
    {
      from: 'components/secrets/UnknownSecretHelpContent.vue',
      to: 'apps/secret/components/UnknownSecretHelpContent.vue',
      action: 'move',
    },
    // Subdirectories in components/secrets/
    {
      from: 'components/secrets/form',
      to: 'apps/secret/components/form',
      action: 'move',
    },
    {
      from: 'components/secrets/metadata',
      to: 'apps/secret/components/metadata',
      action: 'move',
    },
    {
      from: 'components/secrets/branded',
      to: 'apps/secret/components/branded',
      action: 'move',
      notes: 'Keep until views refactored',
    },
    {
      from: 'components/secrets/canonical',
      to: 'apps/secret/components/canonical',
      action: 'move',
      notes: 'Keep until views refactored',
    },
    {
      from: 'components/incoming',
      to: 'apps/secret/components/incoming',
      action: 'move',
    },

    // ========================================================================
    // Workspace App: Dashboard
    // ========================================================================
    {
      from: 'views/dashboard/DashboardContainer.vue',
      to: 'apps/workspace/dashboard/DashboardContainer.vue',
      action: 'move',
      notes: 'Logic moves to composables',
    },
    {
      from: 'views/dashboard/DashboardIndex.vue',
      to: 'apps/workspace/dashboard/DashboardIndex.vue',
      action: 'move',
    },
    {
      from: 'views/dashboard/DashboardRecent.vue',
      to: 'apps/workspace/dashboard/DashboardRecent.vue',
      action: 'move',
    },
    {
      from: 'views/dashboard/DashboardEmpty.vue',
      to: 'apps/workspace/dashboard/DashboardEmpty.vue',
      action: 'move',
    },
    {
      from: 'views/dashboard/DashboardBasic.vue',
      to: 'apps/workspace/dashboard/DashboardBasic.vue',
      action: 'move',
    },
    {
      from: 'views/dashboard/SingleTeamDashboard.vue',
      to: 'apps/workspace/dashboard/SingleTeamDashboard.vue',
      action: 'move',
    },

    // ========================================================================
    // Workspace App: Domains
    // ========================================================================
    {
      from: 'views/dashboard/DashboardDomains.vue',
      to: 'apps/workspace/domains/DomainsList.vue',
      action: 'rename',
    },
    {
      from: 'views/dashboard/DashboardDomainAdd.vue',
      to: 'apps/workspace/domains/DomainAdd.vue',
      action: 'rename',
    },
    {
      from: 'views/dashboard/DashboardDomainVerify.vue',
      to: 'apps/workspace/domains/DomainVerify.vue',
      action: 'rename',
    },
    {
      from: 'views/dashboard/DashboardDomainBrand.vue',
      to: 'apps/workspace/domains/DomainBrand.vue',
      action: 'rename',
    },

    // ========================================================================
    // Workspace App: Account
    // ========================================================================
    {
      from: 'views/account/AccountIndex.vue',
      to: 'apps/workspace/account/AccountIndex.vue',
      action: 'move',
    },
    {
      from: 'views/account/AccountSettings.vue',
      to: 'apps/workspace/account/AccountSettings.vue',
      action: 'move',
    },
    {
      from: 'views/account/ActiveSessions.vue',
      to: 'apps/workspace/account/ActiveSessions.vue',
      action: 'move',
    },
    {
      from: 'views/account/ChangePassword.vue',
      to: 'apps/workspace/account/ChangePassword.vue',
      action: 'move',
    },
    {
      from: 'views/account/CloseAccount.vue',
      to: 'apps/workspace/account/CloseAccount.vue',
      action: 'move',
    },
    {
      from: 'views/account/DataRegion.vue',
      to: 'apps/workspace/account/DataRegion.vue',
      action: 'move',
    },
    {
      from: 'views/account/MfaSettings.vue',
      to: 'apps/workspace/account/MfaSettings.vue',
      action: 'move',
    },
    {
      from: 'views/account/RecoveryCodes.vue',
      to: 'apps/workspace/account/RecoveryCodes.vue',
      action: 'move',
    },
    {
      from: 'views/account/region/AvailableRegions.vue',
      to: 'apps/workspace/account/region/AvailableRegions.vue',
      action: 'move',
    },
    {
      from: 'views/account/region/CurrentRegion.vue',
      to: 'apps/workspace/account/region/CurrentRegion.vue',
      action: 'move',
    },
    {
      from: 'views/account/region/WhyItMatters.vue',
      to: 'apps/workspace/account/region/WhyItMatters.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/ApiSettings.vue',
      to: 'apps/workspace/account/settings/ApiSettings.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/CautionZone.vue',
      to: 'apps/workspace/account/settings/CautionZone.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/ChangeEmail.vue',
      to: 'apps/workspace/account/settings/ChangeEmail.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/NotificationSettings.vue',
      to: 'apps/workspace/account/settings/NotificationSettings.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/OrganizationSettings.vue',
      to: 'apps/workspace/account/settings/OrganizationSettings.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/OrganizationsSettings.vue',
      to: 'apps/workspace/account/settings/OrganizationsSettings.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/PrivacySettings.vue',
      to: 'apps/workspace/account/settings/PrivacySettings.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/ProfileSettings.vue',
      to: 'apps/workspace/account/settings/ProfileSettings.vue',
      action: 'move',
    },
    {
      from: 'views/account/settings/SecurityOverview.vue',
      to: 'apps/workspace/account/settings/SecurityOverview.vue',
      action: 'move',
    },

    // ========================================================================
    // Workspace App: Billing
    // ========================================================================
    {
      from: 'views/billing/BillingOverview.vue',
      to: 'apps/workspace/billing/BillingOverview.vue',
      action: 'move',
    },
    {
      from: 'views/billing/InvoiceList.vue',
      to: 'apps/workspace/billing/InvoiceList.vue',
      action: 'move',
    },
    {
      from: 'views/billing/PlanSelector.vue',
      to: 'apps/workspace/billing/PlanSelector.vue',
      action: 'move',
    },

    // ========================================================================
    // Workspace App: Teams
    // ========================================================================
    {
      from: 'views/teams/TeamsHub.vue',
      to: 'apps/workspace/teams/TeamsHub.vue',
      action: 'move',
    },
    {
      from: 'views/teams/TeamView.vue',
      to: 'apps/workspace/teams/TeamView.vue',
      action: 'move',
    },
    {
      from: 'views/teams/TeamMembers.vue',
      to: 'apps/workspace/teams/TeamMembers.vue',
      action: 'move',
    },
    {
      from: 'views/teams/TeamSettings.vue',
      to: 'apps/workspace/teams/TeamSettings.vue',
      action: 'move',
    },

    // ========================================================================
    // Workspace App: Components
    // ========================================================================
    {
      from: 'components/dashboard',
      to: 'apps/workspace/components/dashboard',
      action: 'move',
    },
    {
      from: 'components/account',
      to: 'apps/workspace/components/account',
      action: 'move',
    },
    {
      from: 'components/billing',
      to: 'apps/workspace/components/billing',
      action: 'move',
    },
    {
      from: 'components/teams',
      to: 'apps/workspace/components/teams',
      action: 'move',
    },
    {
      from: 'components/organizations',
      to: 'apps/workspace/components/organizations',
      action: 'move',
    },

    // ========================================================================
    // Kernel App
    // ========================================================================
    {
      from: 'views/colonel/ColonelIndex.vue',
      to: 'apps/kernel/views/ColonelIndex.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelUsers.vue',
      to: 'apps/kernel/views/ColonelUsers.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelSecrets.vue',
      to: 'apps/kernel/views/ColonelSecrets.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelDomains.vue',
      to: 'apps/kernel/views/ColonelDomains.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelSystem.vue',
      to: 'apps/kernel/views/ColonelSystem.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelSystemAuthDB.vue',
      to: 'apps/kernel/views/ColonelSystemAuthDB.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelSystemDatabase.vue',
      to: 'apps/kernel/views/ColonelSystemDatabase.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelSystemMainDB.vue',
      to: 'apps/kernel/views/ColonelSystemMainDB.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelSystemRedis.vue',
      to: 'apps/kernel/views/ColonelSystemRedis.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelUsageExport.vue',
      to: 'apps/kernel/views/ColonelUsageExport.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/ColonelBannedIPs.vue',
      to: 'apps/kernel/views/ColonelBannedIPs.vue',
      action: 'move',
    },
    {
      from: 'views/colonel/SystemSettings.vue',
      to: 'apps/kernel/views/SystemSettings.vue',
      action: 'move',
    },
    {
      from: 'components/colonel',
      to: 'apps/kernel/components',
      action: 'move',
    },

    // ========================================================================
    // Session App
    // ========================================================================
    {
      from: 'views/auth/Signin.vue',
      to: 'apps/session/views/Login.vue',
      action: 'rename',
    },
    {
      from: 'views/auth/Signup.vue',
      to: 'apps/session/views/Register.vue',
      action: 'rename',
    },
    {
      from: 'views/auth/EmailLogin.vue',
      to: 'apps/session/views/EmailLogin.vue',
      action: 'move',
    },
    {
      from: 'views/auth/MfaVerify.vue',
      to: 'apps/session/views/MfaChallenge.vue',
      action: 'rename',
    },
    {
      from: 'views/auth/PasswordReset.vue',
      to: 'apps/session/views/PasswordReset.vue',
      action: 'move',
    },
    {
      from: 'views/auth/PasswordResetRequest.vue',
      to: 'apps/session/views/PasswordResetRequest.vue',
      action: 'move',
    },
    {
      from: 'views/auth/VerifyAccount.vue',
      to: 'apps/session/views/VerifyAccount.vue',
      action: 'move',
    },
    {
      from: 'components/auth',
      to: 'apps/session/components',
      action: 'move',
    },

    // ========================================================================
    // Shared: Layouts
    // ========================================================================
    {
      from: 'layouts/DefaultLayout.vue',
      to: 'shared/layouts/TransactionalLayout.vue',
      action: 'rename',
    },
    {
      from: 'layouts/ImprovedLayout.vue',
      to: 'shared/layouts/ManagementLayout.vue',
      action: 'rename',
    },
    {
      from: 'layouts/ColonelLayout.vue',
      to: 'shared/layouts/AdminLayout.vue',
      action: 'rename',
    },
    {
      from: 'layouts/QuietLayout.vue',
      to: 'shared/layouts/MinimalLayout.vue',
      action: 'rename',
    },
    {
      from: 'layouts/AccountLayout.vue',
      to: 'shared/layouts/AccountLayout.vue',
      action: 'move',
    },
    {
      from: 'layouts/BaseLayout.vue',
      to: 'shared/layouts/BaseLayout.vue',
      action: 'move',
    },

    // ========================================================================
    // Shared: Components (categorized directories)
    // ========================================================================
    {
      from: 'components/base',
      to: 'shared/components/base',
      action: 'move',
    },
    {
      from: 'components/ui',
      to: 'shared/components/ui',
      action: 'move',
    },
    {
      from: 'components/common',
      to: 'shared/components/common',
      action: 'move',
    },
    {
      from: 'components/icons',
      to: 'shared/components/icons',
      action: 'move',
    },
    {
      from: 'components/logos',
      to: 'shared/components/logos',
      action: 'move',
    },
    {
      from: 'components/layout',
      to: 'shared/components/layout',
      action: 'move',
    },
    {
      from: 'components/navigation',
      to: 'shared/components/navigation',
      action: 'move',
    },
    {
      from: 'components/modals',
      to: 'shared/components/modals',
      action: 'move',
    },
    {
      from: 'components/ctas',
      to: 'shared/components/ctas',
      action: 'move',
    },
    {
      from: 'components/closet',
      to: 'shared/components/closet',
      action: 'move',
    },

    // ========================================================================
    // Shared: Flat Components → Categorized
    // ========================================================================
    // UI Components
    {
      from: 'components/ActivityFeed.vue',
      to: 'shared/components/ui/ActivityFeed.vue',
      action: 'move',
    },
    {
      from: 'components/ButtonGroup.vue',
      to: 'shared/components/ui/ButtonGroup.vue',
      action: 'move',
    },
    {
      from: 'components/CopyButton.vue',
      to: 'shared/components/ui/CopyButton.vue',
      action: 'move',
    },
    {
      from: 'components/SplitButton.vue',
      to: 'shared/components/ui/SplitButton.vue',
      action: 'move',
    },
    {
      from: 'components/DetailField.vue',
      to: 'shared/components/ui/DetailField.vue',
      action: 'move',
    },
    {
      from: 'components/EmptyState.vue',
      to: 'shared/components/ui/EmptyState.vue',
      action: 'move',
    },
    {
      from: 'components/ErrorDisplay.vue',
      to: 'shared/components/ui/ErrorDisplay.vue',
      action: 'move',
    },
    {
      from: 'components/InfoTooltip.vue',
      to: 'shared/components/ui/InfoTooltip.vue',
      action: 'move',
    },
    {
      from: 'components/MoreInfoText.vue',
      to: 'shared/components/ui/MoreInfoText.vue',
      action: 'move',
    },
    {
      from: 'components/QuoteBlock.vue',
      to: 'shared/components/ui/QuoteBlock.vue',
      action: 'move',
    },
    {
      from: 'components/QuoteSection.vue',
      to: 'shared/components/ui/QuoteSection.vue',
      action: 'move',
    },
    {
      from: 'components/StatusBar.vue',
      to: 'shared/components/ui/StatusBar.vue',
      action: 'move',
    },
    {
      from: 'components/StarsRating.vue',
      to: 'shared/components/ui/StarsRating.vue',
      action: 'move',
    },
    {
      from: 'components/GlobalBroadcast.vue',
      to: 'shared/components/ui/GlobalBroadcast.vue',
      action: 'move',
    },
    {
      from: 'components/GithubCorner.vue',
      to: 'shared/components/ui/GithubCorner.vue',
      action: 'move',
    },
    {
      from: 'components/MovingGlobules.vue',
      to: 'shared/components/ui/MovingGlobules.vue',
      action: 'move',
    },
    {
      from: 'components/ThemeToggle.vue',
      to: 'shared/components/ui/ThemeToggle.vue',
      action: 'move',
    },
    {
      from: 'components/LanguageToggle.vue',
      to: 'shared/components/ui/LanguageToggle.vue',
      action: 'move',
    },
    {
      from: 'components/JurisdictionToggle.vue',
      to: 'shared/components/ui/JurisdictionToggle.vue',
      action: 'move',
    },
    {
      from: 'components/MinimalDropdownMenu.vue',
      to: 'shared/components/ui/MinimalDropdownMenu.vue',
      action: 'move',
    },
    {
      from: 'components/EmailObfuscator.vue',
      to: 'shared/components/ui/EmailObfuscator.vue',
      action: 'move',
    },

    // Modal Components
    {
      from: 'components/ConfirmDialog.vue',
      to: 'shared/components/modals/ConfirmDialog.vue',
      action: 'move',
    },
    {
      from: 'components/SimpleModal.vue',
      to: 'shared/components/modals/SimpleModal.vue',
      action: 'move',
    },

    // Form Components
    {
      from: 'components/BasicFormAlerts.vue',
      to: 'shared/components/forms/BasicFormAlerts.vue',
      action: 'move',
    },
    {
      from: 'components/PasswordStrengthChecker.vue',
      to: 'shared/components/forms/PasswordStrengthChecker.vue',
      action: 'move',
    },

    // Domain Components → Workspace
    {
      from: 'components/DomainForm.vue',
      to: 'apps/workspace/components/domains/DomainForm.vue',
      action: 'move',
    },
    {
      from: 'components/DomainInput.vue',
      to: 'apps/workspace/components/domains/DomainInput.vue',
      action: 'move',
    },
    {
      from: 'components/DomainsTable.vue',
      to: 'apps/workspace/components/domains/DomainsTable.vue',
      action: 'move',
    },
    {
      from: 'components/DomainVerificationInfo.vue',
      to: 'apps/workspace/components/domains/DomainVerificationInfo.vue',
      action: 'move',
    },
    {
      from: 'components/VerifyDomainDetails.vue',
      to: 'apps/workspace/components/domains/VerifyDomainDetails.vue',
      action: 'move',
    },
    {
      from: 'components/CustomDomainPreview.vue',
      to: 'apps/workspace/components/domains/CustomDomainPreview.vue',
      action: 'move',
    },

    // Feedback Components → Secret
    {
      from: 'components/FeedbackForm.vue',
      to: 'apps/secret/components/support/FeedbackForm.vue',
      action: 'move',
    },
    {
      from: 'components/FeedbackModalForm.vue',
      to: 'apps/secret/components/support/FeedbackModalForm.vue',
      action: 'move',
    },
    {
      from: 'components/FeedbackToggle.vue',
      to: 'apps/secret/components/support/FeedbackToggle.vue',
      action: 'move',
    },

    // Homepage Components → Secret
    {
      from: 'components/HomepageTaglines.vue',
      to: 'apps/secret/components/conceal/HomepageTaglines.vue',
      action: 'move',
    },
    {
      from: 'components/DisabledHomepageTaglines.vue',
      to: 'apps/secret/components/conceal/DisabledHomepageTaglines.vue',
      action: 'move',
    },
    {
      from: 'components/HomepageAccessToggle.vue',
      to: 'apps/secret/components/conceal/HomepageAccessToggle.vue',
      action: 'move',
    },

    // ========================================================================
    // Shared: Errors
    // ========================================================================
    {
      from: 'views/errors/ErrorNotFound.vue',
      to: 'shared/components/errors/ErrorNotFound.vue',
      action: 'move',
    },
    {
      from: 'views/errors/ErrorPage.vue',
      to: 'shared/components/errors/ErrorPage.vue',
      action: 'move',
    },
    {
      from: 'views/NotFound.vue',
      to: null,
      action: 'delete',
      notes: 'Use shared ErrorNotFound',
    },

    // ========================================================================
    // Shared: Stores
    // ========================================================================
    {
      from: 'stores',
      to: 'shared/stores',
      action: 'move',
      notes: 'All stores are shared across apps',
    },

    // ========================================================================
    // Shared: Composables
    // ========================================================================
    {
      from: 'composables',
      to: 'shared/composables',
      action: 'move',
      notes: 'Move wholesale first, then relocate app-specific ones',
    },
  ];
}
