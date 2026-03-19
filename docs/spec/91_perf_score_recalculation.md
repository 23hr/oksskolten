# Oksskolten Spec — Score Recalculation Optimization

## Background

Oksskolten's engagement score is computed as the product of an engagement value (based on user actions: like/bookmark/read/translate) and a time decay factor.

```
score = engagement × decay

engagement = (liked_at ? 10 : 0)
           + (bookmarked_at ? 5 : 0)
           + (full_text_translated ? 3 : 0)
           + (read_at ? 2 : 0)

decay = 1.0 / (1.0 + days_since_activity × 0.05)
  where days_since_activity = julianday('now') - julianday(COALESCE(read_at, published_at, fetched_at))
```

Score updates currently happen through two paths:

1. **Event-driven (already implemented)**: `updateScoreDb(id)` is called immediately on like/bookmark/read/translate/unseen actions
2. **Cron batch (every 5 minutes)**: `recalculateScores()` UPDATEs all articles that have any engagement

Since event-driven updates already handle engagement changes instantly, the cron batch's only remaining role is **periodic time-decay refresh**. Running every 5 minutes is excessive, and CPU cost scales linearly with article count.

## Current Problem

`recalculateScores()` in `server/db/articles.ts`:

```sql
UPDATE articles SET score = (score expression)
WHERE liked_at IS NOT NULL
   OR bookmarked_at IS NOT NULL
   OR read_at IS NOT NULL
   OR full_text_translated IS NOT NULL
   OR score > 0
```

Issues:

- Articles with `score > 0` remain in the recalculation set permanently
- Recalculation runs every 5 minutes even when no engagement state has changed
- Event-driven updates already reflect engagement changes instantly; the cron's effective purpose is limited to time-decay refresh

## Existing Score Update Implementation

### Event-Driven (`server/db/articles.ts`)

| Function | Trigger | Action |
|---|---|---|
| `markArticleLiked()` | like/unlike | `updateScoreDb(id)` |
| `markArticleBookmarked()` | bookmark/unbookmark | `updateScoreDb(id)` |
| `recordArticleRead()` | opening an article | `updateScoreDb(id)` |
| `markArticleSeen()` | marking unseen | `updateScoreDb(id)` |
| Translation complete (`server/routes/articles.ts`) | translate API | `updateScore(id)` (DB + Meilisearch sync) |

### Where Scores Are Used

| Usage | Reference Method | Decay Freshness Important? |
|---|---|---|
| `GET /api/articles?sort=score` | Stored `score` column | Somewhat — affects sort order |
| `getArticlesByIds()` (search results) | Dynamically computed via `scoreExpr()` | No — computed each time |
| Meilisearch index | Synced `score` value | Low — primarily for filtering |
| AI chat tools | Via search results | No — dynamically computed |
| Smart Floor | Not used | No |

## Approach: Replace 5-Minute Cron Batch with Daily Decay Batch

Since event-driven updates already handle engagement changes instantly, the cron batch's role is reduced to daily time-decay refresh only.

### Changes

1. `server/index.ts`: Remove the `recalculateScores()` call from the feed-fetch cron (`CRON_SCHEDULE`)
2. `server/index.ts`: Add a new daily cron job that runs `recalculateScores()` on a daily schedule
3. After the daily batch completes, bulk-sync updated article scores to the Meilisearch index
4. Do not change the `recalculateScores()` WHERE clause (use existing logic as-is)

### Daily Batch Schedule

- Default: `0 3 * * *` (daily at 3:00 AM)
- Configurable via the `SCORE_RECALC_SCHEDULE` environment variable
- Document the default in `.env.example`

### Meilisearch Bulk Sync

After the daily batch completes, fetch articles matching the same WHERE clause as `recalculateScores()` and bulk-sync their scores to Meilisearch. `recalculateScores()` itself is not modified; a separate sync function is added.

```typescript
// Daily batch flow
const { updated } = recalculateScores()
if (updated > 0) {
  syncAllScoredArticlesToSearch()
}
```

`syncAllScoredArticlesToSearch()` is added to `server/search/sync.ts`. It queries `id, score` using the same WHERE clause as the batch and performs a partial document update in Meilisearch. Since it runs once daily, performance impact is minimal.

### Key Files

| File | Description |
|---|---|
| `server/index.ts` | Cron schedule changes |
| `server/search/sync.ts` | `syncAllScoredArticlesToSearch()` function |
| `.env.example` | `SCORE_RECALC_SCHEDULE` documentation |

### Logging

Follow existing log format at `info` level:

```
[cron] Daily score recalc: 142 articles updated
[cron] Score sync to search: 142 articles
```

### Testing

- Existing score persistence tests in `server/db/articles.test.ts` are preserved as-is
- Add unit tests for `syncAllScoredArticlesToSearch()` in `server/search/sync.ts`

### Scope

This spec is limited to:

- Removing `recalculateScores()` from the feed-fetch cron
- Adding a daily batch cron
- Adding the Meilisearch bulk sync function

Out of scope:
- Refactoring event-driven score updates (`updateScoreDb()` / `updateScore()`)
- Changing the score formula
- Schema changes

### Error Handling

Follow existing cron error handling: try-catch with `log.error`. No retries (the next daily batch will re-run automatically). If `recalculateScores()` errors, skip the Meilisearch sync.

```typescript
try {
  const { updated } = recalculateScores()
  log.info(`[cron] Daily score recalc: ${updated} articles updated`)
  if (updated > 0) {
    syncAllScoredArticlesToSearch()
    log.info(`[cron] Score sync to search: ${updated} articles`)
  }
} catch (err) {
  log.error('[cron] Daily score recalc error:', err)
}
```

### Concurrency

No mutex is needed between the daily batch and the feed-fetch cron. SQLite's WAL mode serializes writes, so there is no data corruption risk. If the batch and an event-driven update overlap, whichever runs last wins — both use the same `scoreExpr()`, so the difference is negligible (only seconds of `julianday('now')` drift).

### Migration

No schema changes required. Deploy the code change only. After deployment, the next feed-fetch cron cycle will no longer run `recalculateScores()`, and the daily batch will first execute at the configured schedule time.

## Expected Impact

- Recalculation frequency reduced from every 5 minutes (288×/day) to once daily
- CPU cost reduced by ~1/288
- Score immediacy is maintained by event-driven updates
- Time decay refresh is delayed by up to 24 hours, which is acceptable for an RSS reader (decay factor 0.05 means daily drift is negligible)
- Meilisearch scores are refreshed daily

