#!/usr/bin/env python3
import json
import re
from pathlib import Path
from typing import Optional

"""
Translation Key Analysis and Migration Template Generator

This script analyzes existing translation keys to generate standardized structure
templates and migration mappings. It uses pattern recognition and file location
analysis to categorize translation keys into a logical hierarchy.

Usage:
    python migrate-keys.py

Input:
    - keys_sorted.json: File containing translation keys with file usage information

Output:
    - nested.json: Template structure for i18n hierarchy with categorized keys
    - migrations.json: Mapping from old translation keys to new hierarchical paths

Dependencies:
    - Python 3.6+
    - Standard library only (json, re, pathlib)

The categorization system organizes keys into functional groups:
- status: State indicators and condition labels
- buttons: Interactive UI elements
- actions: User operations and commands
- feedback: Success, error, and information messages
- labels: Text display elements
- features: Feature-specific translations
- time: Date and time related text
- formats: Number and date formatting rules

Keys are categorized using:
1. View file location patterns
2. Key name prefixes and patterns
3. Semantic content analysis
"""


"""
    Category Rules (in order of precedence):

    1. File Location Based:
        - views/auth/* -> features.authentication
            Example: views/auth/LoginForm.vue -> features.authentication
        - views/dashboard/* -> pages.dashboard
            Example: views/dashboard/Overview.vue -> pages.dashboard
        - views/profile/* -> pages.profile
            Example: views/profile/Settings.vue -> pages.profile

    2. Key Name Prefixes:
        - web.common.* -> labels
            Example: web.common.username -> labels
        - common.* -> labels
            Example: common.email -> labels
        - error.* -> feedback.error
            Example: error.invalid_input -> feedback.error
        - success.* -> feedback.success
            Example: success.saved -> feedback.success
        - btn.* -> buttons
            Example: btn.submit -> buttons
        - action.* -> actions
            Example: action.download -> actions

    3. Key Name Patterns:
        Status:
            - *status*, *state*, *active*, *inactive*, *enabled*, *disabled*
            Example: user.status.active -> status

        Buttons:
            - *button*, *btn*, *submit*, *cancel*, *save*, *delete*, *edit*
            Example: save_changes_button -> buttons

        Actions:
            - *upload*, *download*, *share*, *copy*, *paste*, *export*, *import*
            Example: document_share -> actions

        Feedback:
            - *success* -> feedback.success
            - *error*, *fail* -> feedback.error
            - *info*, *notice* -> feedback.info
            Example: operation_failed -> feedback.error

        Authentication:
            - *login*, *signin*, *register*, *password*, *auth*
            Example: login_failed -> features.authentication

        Notifications:
            - *notification*, *alert*
            Example: new_message_notification -> features.notifications

        Labels:
            - *label*, *title*, *heading* -> labels
            - *form*, *input*, *field* -> labels.form
            - *table*, *grid*, *list* -> labels.table
            Example: form_field_required -> labels.form

        Time:
            - *time*, *date*, *duration*, *period*
            Example: event_duration -> time

        Formats:
            - *format*, *locale*
            Example: date_format -> formats

    4. Default:
        - Keys that don't match any patterns -> other

    Args:
        key: The translation key string
        filepath: The file path where the key is used

    Returns:
        str: The determined category path (dot-separated)

    Examples:
        >>> determine_category("btn.save", "components/Button.vue")
        'buttons'
        >>> determine_category("login.failed", "views/auth/LoginForm.vue")
        'features.authentication'
        >>> determine_category("table.no_data", "components/Table.vue")
        'labels.table'
"""

"""
Output Files Purpose and Structure:

1. nested.json
    Purpose: Primary locale structure template for the application
    Format: Hierarchical JSON matching standardized i18n structure
    Usage:
        - Base template for all language files
        - Import into vue-i18n as default structure
        - Reference for maintainers adding new translations
    Example:
        {
          "status": {
            "active": "",
            "inactive": ""
          },
          "buttons": {
            "submit": "",
            "cancel": ""
          }
        }

2. migrations.json
    Purpose: Mapping file for automated migration of existing keys
    Format: Flat JSON with old->new key mappings
    Usage:
        - Input for migration scripts
        - Documentation of key changes
        - Validation reference
    Example:
        {
          "btn.save": "buttons.save",
          "error.generic": "feedback.error.generic"
        }

3. audit.json (recommended additional output)
    Purpose: Documentation of categorization decisions
    Format: JSON with key metadata
    Usage:
        - Debugging categorization
        - Documentation
        - Future refactoring reference
    Example:
        {
          "oldKey": "btn.save",
          "newKey": "buttons.save",
          "category": "buttons",
          "files": ["path/to/file"],
          "matchedRule": "prefix:btn"
        }
"""

def get_view_category(filepath: str) -> Optional[str]:
    """
    Determine category based on view file location

    Args:
        filepath: Path to view file

    Returns:
        Category string or None if not determinable
    """
    if not filepath:
        return None

    path = Path(filepath)
    parts = path.parts

    # View directory mappings
    view_categories = {
        'auth': 'features.authentication',
        'dashboard': 'pages.dashboard',
        'profile': 'pages.profile',
        'settings': 'features.settings',
        'notifications': 'features.notifications'
    }

    for part in parts:
        if part.lower() in view_categories:
            return view_categories[part.lower()]

    return None


def analyze_patterns(key: str) -> dict:
    """
    Analyzes common patterns in key names to suggest proper categorization

    Returns dict with:
        - suggested_category: str
        - confidence: float (0-1)
        - pattern_matched: str
    """
    # UI Element Patterns
    ui_patterns = {
        r'(button|btn)': 'buttons',
        r'(modal|dialog)': 'components',
        r'(form|input|field)': 'labels.form',
        r'(table|grid|list)': 'labels.table',
        r'(title|heading)': 'labels.title',
        r'(placeholder|hint)': 'labels.form'
    }

    # Action Patterns
    action_patterns = {
        r'(create|update|delete|edit|manage)': 'actions',
        r'(upload|download|share|copy|paste)': 'actions',
        r'(submit|send|receive|generate)': 'actions'
    }

    # Status/State Patterns
    status_patterns = {
        r'(status|state)': 'status',
        r'(active|inactive|enabled|disabled)': 'status',
        r'(success|error|warning|info)': 'feedback',
        r'(loading|processing)': 'status'
    }

    # Feature Patterns
    feature_patterns = {
        r'(auth|login|register|password)': 'features.authentication',
        r'(notification|alert)': 'features.notifications',
        r'(profile|account)': 'features.profile',
        r'(dashboard)': 'pages.dashboard',
        r'(settings|preferences)': 'features.settings'
    }

    # Time Patterns
    time_patterns = {
        r'(time|date|duration|period)': 'time',
        r'(expires|expiration)': 'time',
        r'(schedule|calendar)': 'time'
    }

    # Format Patterns
    format_patterns = {
        r'(format|locale|language)': 'formats',
        r'(currency|number|decimal)': 'formats.number',
        r'(date|time)format': 'formats.date'
    }

    all_patterns = {
        **ui_patterns,
        **action_patterns,
        **status_patterns,
        **feature_patterns,
        **time_patterns,
        **format_patterns
    }

    # Check patterns
    for pattern, category in all_patterns.items():
        if re.search(pattern, key.lower()):
            return {
                'suggested_category': category,
                'confidence': 0.8,
                'pattern_matched': pattern
            }

    # Check prefixes
    prefixes = {
        'web.COMMON': 'labels',
        'web.STATUS': 'status',
        'web.LABELS': 'labels',
        'web.FEATURES': 'features',
        'web.account': 'features.profile',
        'web.auth': 'features.authentication'
    }

    for prefix, category in prefixes.items():
        if key.startswith(prefix):
            return {
                'suggested_category': category,
                'confidence': 0.9,
                'pattern_matched': f'prefix:{prefix}'
            }

    return {
        'suggested_category': 'other',
        'confidence': 0.1,
        'pattern_matched': None
    }

def determine_category(key: str, filepath: str) -> str:
    """
    Determine final category for a translation key
    """
    # First try pattern analysis
    analysis = analyze_patterns(key)

    if analysis['confidence'] > 0.7:
        return analysis['suggested_category']

    # Then try file path based categorization
    if filepath and 'views/' in filepath:
        view_category = get_view_category(filepath)
        if view_category:
            return view_category

    # For low confidence matches, use semantic categorization
    key_lower = key.lower()

    if any(word in key_lower for word in ['cancel', 'confirm', 'submit', 'save']):
        return 'buttons'

    if any(word in key_lower for word in ['error', 'success', 'warning']):
        return 'feedback'

    if any(word in key_lower for word in ['title', 'label', 'heading']):
        return 'labels'

    # If still uncategorized, check key structure
    parts = key.split('.')
    if len(parts) > 1:
        # Use first part as category if it matches known categories
        first_part = parts[0].lower()
        if first_part in ['status', 'button', 'action', 'label']:
            return first_part + 's'

    return 'other'

def create_nested_structure(keys_data: dict) -> dict:
    """
    Create nested locale structure from flat keys
    """
    output = {
        'status': {},
        'buttons': {},
        'actions': {},
        'feedback': {
            'success': {},
            'error': {},
            'info': {}
        },
        'labels': {
            'title': {},
            'form': {},
            'table': {}
        },
        'features': {
            'authentication': {
                'login': {},
                'register': {},
                'resetPassword': {}
            },
            'notifications': {}
        },
        'pages': {
            'home': {},
            'dashboard': {},
            'profile': {}
        },
        'time': {},
        'formats': {
            'date': {},
            'number': {}
        },
        'other': {}  # Include other category
    }

    for key_obj in keys_data['keys']:
        old_key = key_obj['oldkey']
        files = key_obj.get('files', [])
        filepath = files[0] if files else ""

        category = determine_category(old_key, filepath)

        # Split category path and create nested structure
        parts = category.split('.')
        current = output

        # Create intermediate categories if they don't exist
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]

        # Add key to appropriate category
        final_category = parts[-1]
        if final_category not in current:
            current[final_category] = {}
        current[final_category][old_key] = ""

    return output

def main():
    # Read input keys
    with open('keys_sorted.json') as f:
        keys_data = json.load(f)

    # Generate nested structure
    nested = create_nested_structure(keys_data)

    # Write output with pretty formatting
    with open('nested.json', 'w', encoding='utf-8') as f:
        json.dump(nested, f, indent=2, ensure_ascii=False)

    # Generate migration mappings
    migrations = {}
    for key_obj in keys_data['keys']:
        old_key = key_obj['oldkey']
        files = key_obj.get('files', [])
        filepath = files[0] if files else ""
        category = determine_category(old_key, filepath)
        new_key = f"{category}.{old_key}"
        migrations[old_key] = new_key

    # Write migrations
    with open('migrations.json', 'w', encoding='utf-8') as f:
        json.dump(migrations, f, indent=2, ensure_ascii=False)

if __name__ == '__main__':
    main()
