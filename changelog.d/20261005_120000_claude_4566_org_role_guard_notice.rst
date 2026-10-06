.. A new scriv changelog fragment.

Fixed
-----

- Accepting an organization invitation now lands the invitee on a page
  they can open: the organization's settings for a new admin, the
  dashboard for a new member. The invite page used to send everyone to
  the owner-only organizations list, which bounced invitees on to the
  dashboard with no explanation. The "already accepted" view links the
  same way (#4566).
- A signed-in user redirected away from a page that needs an
  organization owner or admin role now sees a notice instead of arriving
  on the dashboard silently: the requirement when their role is known,
  or that access could not be confirmed when the organization lookup
  failed (#4566).
