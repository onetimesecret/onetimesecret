.. A new scriv changelog fragment.

Fixed
-----

- Burning a secret now honors the parsed ``continue`` confirmation flag instead of the raw request parameter. ``BurnSecret`` (v1 and v2) greenlighted the destructive burn on ``params['continue']`` directly, and because any non-empty string is truthy in Ruby a caller that explicitly sent ``continue=false`` would still burn the secret. Only ``true`` / ``'true'`` now confirms a burn, matching the reveal/show actions. (#3454)
