.. A new scriv changelog fragment.

Changed
-------

- Lettermint sender domain removal now relies on ``lettermint`` 0.2.1, which
  raises ``NotFoundError`` with the API error code on HTTP 404. A domain that
  Lettermint reports as ``RESOURCE_NOT_FOUND`` is recorded as already absent;
  a 404 from a router or proxy, or one without that code, is still recorded
  as a failed cleanup. Lettermint error details in logs and cleanup messages
  include the API error code when the response carries one.
