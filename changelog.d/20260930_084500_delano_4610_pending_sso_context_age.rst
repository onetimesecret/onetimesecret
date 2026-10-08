.. A new scriv changelog fragment.

Changed
-------

- A single sign-on flow started on a custom domain now has ten minutes to
  complete. After that the pending sign-in is dropped from the session and
  the visitor starts again from the sign-in page. A sign-in in progress
  while this release is deployed also has to be started again. (#4610)
