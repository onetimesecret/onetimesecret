// src/schemas/api/account/responses/colonel-trends.ts
//
// Per-resource colonel/admin schemas for the overview trends (observability).
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are untouched
// (the Zod tripwire, epic non-goal). One shape for the net-new endpoint:
//
//   - GetTrends → GET /api/colonel/trends (30-day per-day activity series)
//
// Shape verified against the live logic class
// (apps/api/colonel/logic/colonel/get_trends.rb) over Onetime::DailyMetric.
// Series are UTC-day buckets, oldest first, zero-filled — and forward-only
// (no backfill), so the UI presents them as "collecting since first data
// point" rather than implying pre-instrumentation history.

import { z } from 'zod';

/** One day bucket: `date` is the UTC calendar day as ISO `YYYY-MM-DD`. */
export const colonelTrendPointSchema = z.object({
  date: z.string(),
  count: z.number(),
});

/** Trends response details: fixed window length + one series per metric. */
export const colonelTrendsDetailsSchema = z.object({
  days: z.number(),
  series: z.object({
    signups: z.array(colonelTrendPointSchema),
    secrets_created: z.array(colonelTrendPointSchema),
  }),
});

export type ColonelTrendPoint = z.infer<typeof colonelTrendPointSchema>;
export type ColonelTrendsDetails = z.infer<typeof colonelTrendsDetailsSchema>;
