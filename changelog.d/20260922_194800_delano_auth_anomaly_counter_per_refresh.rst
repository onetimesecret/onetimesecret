.. A new scriv changelog fragment.

Fixed
-----

- A tab could reload without warning after a long outage. The session
  coordinator counted anomalous snapshots across its whole lifetime and reset
  the count only when a snapshot applied, so one anomaly whose retry failed
  at the network kept counting, and the next unrelated anomaly, hours later,
  forced a page load instead of the one retry it is owed. The count now
  belongs to a single refresh: a second anomaly forces the reload only when
  it is the immediate retry's own answer.
