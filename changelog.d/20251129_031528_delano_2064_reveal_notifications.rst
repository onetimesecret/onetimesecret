.. A new scriv changelog fragment.

Added
-----

- Secret reveal notifications: Users can now opt-in to receive email notifications when their secrets are viewed. Enable this feature in Account Settings > Notifications.
- New notification settings page at ``/account/settings/profile/notifications`` for managing email notification preferences.
- ``notify_on_reveal`` field on Customer model to store user notification preference.

AI Assistance
-------------

- Claude assisted with full-stack implementation including backend (Ruby email templates, API endpoint, reveal flow integration) and frontend (Vue component, Pinia store, TypeScript schema, i18n strings).
