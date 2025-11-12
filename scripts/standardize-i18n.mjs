#!/usr/bin/env node

import fs from 'fs';
import path from 'path';

/**
 * Script to standardize i18n imports in Vue files
 * Replaces $t() with t() and adds necessary imports
 */

const files = [
  'src/views/secrets/canonical/ShowSecret.vue',
  'src/views/secrets/ShowMetadata.vue',
  'src/views/secrets/BurnSecret.vue',
  'src/views/dashboard/DashboardDomains.vue',
  'src/views/dashboard/DashboardDomainVerify.vue',
  'src/views/auth/EmailLogin.vue',
  'src/views/account/CloseAccount.vue',
  'src/views/account/AccountSettings.vue',
  'src/views/DisabledHomepage.vue',
  'src/views/DisabledUI.vue',
  'src/layouts/QuietLayout.vue',
  'src/components/secrets/metadata/SecretLink.vue',
  'src/components/secrets/metadata/BurnButtonForm.vue',
  'src/components/secrets/metadata/MetadataFAQ.vue',
  'src/components/secrets/form/SecretForm.vue',
  'src/components/secrets/canonical/SecretConfirmationForm.vue',
  'src/components/secrets/branded/SecretConfirmationForm.vue',
  'src/components/secrets/SecretLinksTableRowActions.vue',
  'src/components/secrets/SecretMetadataTable.vue',
  'src/components/secrets/SecretLinksTable.vue',
  'src/components/secrets/SecretLinksTableRow.vue',
  'src/components/modals/settings/JurisdictionInfo.vue',
  'src/components/modals/settings/JurisdictionTab.vue',
  'src/components/layout/FooterLinks.vue',
  'src/components/layout/BrandedMastHead.vue',
  'src/components/dashboard/InstructionsModal.vue',
  'src/components/common/LanguageButton.vue',
  'src/components/common/CycleButtonText.vue',
  'src/components/base/BaseShowSecret.vue',
  'src/components/auth/SignInForm.vue',
  'src/components/auth/SignUpForm.vue',
  'src/components/auth/LockoutAlert.vue',
  'src/components/auth/MagicLinkForm.vue',
  'src/components/account/SessionListItem.vue',
  'src/components/auth/AuthView.vue',
  'src/components/account/AccountDeleteButtonWithModalForm.vue',
  'src/components/account/BrowserTypeToggle.vue',
  'src/components/account/APIKeyCard.vue',
  'src/components/StatusBar.vue',
  'src/components/VerifyDomainDetails.vue',
  'src/components/PasswordStrengthChecker.vue',
  'src/components/SplitButton.vue',
  'src/components/JurisdictionToggle.vue',
  'src/components/FeedbackModalForm.vue',
  'src/components/EmptyState.vue',
  'src/components/FeedbackForm.vue',
  'src/components/DomainForm.vue',
  'src/components/account/DomainBrandView.vue',
  'src/components/BasicFormAlerts.vue',
  'src/components/common/CycleButton.vue',
  'src/components/common/ToggleWithIcon.vue',
  'src/components/ConfirmDialog.vue',
  'src/components/ctas/PlansElevateCta.vue',
  'src/components/CustomDomainPreview.vue',
  'src/components/dashboard/BrowserPreviewFrame.vue',
  'src/components/dashboard/DomainHeader.vue',
  'src/components/dashboard/DomainsTableActionsCell.vue',
  'src/components/dashboard/DomainsTableDomainCell.vue',
  'src/components/DomainInput.vue',
  'src/components/DomainsTable.vue',
  'src/components/GithubCorner.vue',
  'src/components/GlobalBroadcast.vue',
  'src/components/HomepageAccessToggle.vue',
  'src/components/HomepageTaglines.vue',
  'src/components/layout/MicroFooter.vue',
  'src/components/layout/QuietFooter.vue',
  'src/components/layout/SecretFooterAttribution.vue',
  'src/components/MinimalDropdownMenu.vue',
  'src/components/modals/FeedbackModal.vue',
  'src/components/modals/NeedHelpModal.vue',
  'src/components/modals/settings/GeneralTab.vue',
  'src/components/modals/settings/JurisdictionList.vue',
  'src/components/modals/SettingsModal.vue',
  'src/components/QuoteBlock.vue',
  'src/components/QuoteSection.vue',
  'src/components/secrets/branded/SecretDisplayCase.vue',
  'src/components/secrets/form/ConcealButton.vue',
  'src/components/secrets/form/GenerateButton.vue',
  'src/components/secrets/form/SecretContentInputArea.vue',
  'src/components/secrets/metadata/TimelineDisplay.vue',
  'src/components/secrets/SecretDisplayHelpContent.vue',
  'src/components/secrets/SecretRecipientHelpContent.vue',
  'src/components/secrets/UnknownSecretHelpContent.vue',
  'src/components/SimpleModal.vue',
  'src/components/ThemeToggle.vue',
  'src/views/BrandedHomepage.vue',
  'src/views/dashboard/DashboardDomainAdd.vue',
  'src/views/errors/ErrorNotFound.vue',
  'src/views/errors/ErrorPage.vue',
  'src/views/Feedback.vue',
  'src/views/NotFound.vue',
  'src/views/secrets/branded/UnknownSecret.vue',
  'src/views/secrets/canonical/UnknownSecret.vue',
  'src/views/secrets/UnknownMetadata.vue',
];

function processFile(filePath) {
  const fullPath = path.join(process.cwd(), filePath);

  if (!fs.existsSync(fullPath)) {
    console.error(`File not found: ${filePath}`);
    return false;
  }

  let content = fs.readFileSync(fullPath, 'utf8');

  // Check if file uses $t()
  if (!content.includes('$t(')) {
    console.log(`Skipping ${filePath} - no $t() usage found`);
    return false;
  }

  // Find script setup section
  const scriptSetupMatch = content.match(/<script\s+setup[^>]*>([\s\S]*?)<\/script>/);
  if (!scriptSetupMatch) {
    console.error(`No <script setup> found in ${filePath}`);
    return false;
  }

  let scriptContent = scriptSetupMatch[1];
  const scriptStart = scriptSetupMatch.index + scriptSetupMatch[0].indexOf('>') + 1;
  const scriptEnd = scriptSetupMatch.index + scriptSetupMatch[0].lastIndexOf('</script>');

  // Check if already has useI18n import
  const hasI18nImport = scriptContent.includes("from 'vue-i18n'");
  const hasUseI18n = scriptContent.includes('useI18n()');

  let newScriptContent = scriptContent;

  // Add import if not present
  if (!hasI18nImport) {
    // Find the last import statement
    const imports = scriptContent.match(/^import\s+.*?;$/gm);
    if (imports && imports.length > 0) {
      const lastImport = imports[imports.length - 1];
      const lastImportIndex = scriptContent.indexOf(lastImport) + lastImport.length;
      newScriptContent =
        scriptContent.slice(0, lastImportIndex) +
        "\nimport { useI18n } from 'vue-i18n';" +
        scriptContent.slice(lastImportIndex);
    } else {
      // No imports found, add at the beginning
      newScriptContent = "import { useI18n } from 'vue-i18n';\n" + scriptContent;
    }
  }

  // Add useI18n destructuring if not present
  if (!hasUseI18n) {
    // Find a good place to add it - after all imports and before other code
    // Look for the first non-import, non-comment, non-blank line
    const lines = newScriptContent.split('\n');
    let insertIndex = 0;
    let inImportSection = true;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line === '' || line.startsWith('//') || line.startsWith('/*') || line.startsWith('*')) {
        continue;
      }
      if (line.startsWith('import ')) {
        insertIndex = i + 1;
      } else if (inImportSection && !line.startsWith('import ')) {
        inImportSection = false;
        // Add blank line and useI18n after imports
        lines.splice(insertIndex, 0, '', 'const { t } = useI18n();');
        break;
      }
    }

    if (inImportSection) {
      // Only imports in the file, add at the end
      lines.push('', 'const { t } = useI18n();');
    }

    newScriptContent = lines.join('\n');
  }

  // Replace the script content
  content =
    content.slice(0, scriptStart) +
    newScriptContent +
    content.slice(scriptEnd);

  // Replace $t( with t( in template section
  // Use a regex to match $t( but not inside script tags
  const templateMatch = content.match(/<template>([\s\S]*?)<\/template>/);
  if (templateMatch) {
    const templateContent = templateMatch[1];
    const newTemplateContent = templateContent.replace(/\$t\(/g, 't(');
    content = content.replace(templateMatch[0], `<template>${newTemplateContent}</template>`);
  }

  // Write back to file
  fs.writeFileSync(fullPath, content, 'utf8');
  console.log(`✓ Updated ${filePath}`);
  return true;
}

// Process all files
let successCount = 0;
let failCount = 0;

files.forEach(file => {
  try {
    if (processFile(file)) {
      successCount++;
    } else {
      failCount++;
    }
  } catch (error) {
    console.error(`Error processing ${file}:`, error.message);
    failCount++;
  }
});

console.log(`\nComplete: ${successCount} files updated, ${failCount} files skipped/failed`);
