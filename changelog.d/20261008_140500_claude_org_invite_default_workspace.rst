.. A new scriv changelog fragment.

Added
-----

- The Organizations page has a "Make default" action. The chosen
  organization is where you land after signing in, and it becomes the
  current workspace straight away.

Fixed
-----

- Members of more than one organization now get the workspace switcher.
  Before, it appeared only for owners on a plan that allows several
  organizations, so a free-plan user who joined a company's paid
  organization had no way to switch to it.
- The "Default" label marks your own default organization only. An
  organization you joined that is its owner's default workspace no longer
  shows as yours, and the colonel customer page labels the customer's
  default the same way.
- Accepting an invitation switches you to the organization you joined.
- When you have not chosen a default, sign-in falls back to the default
  workspace you own, not to another owner's default workspace you are a
  member of.
