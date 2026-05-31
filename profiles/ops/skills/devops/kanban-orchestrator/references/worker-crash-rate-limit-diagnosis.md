# Worker Crash Diagnosis — Rate Limits

## Symptom
Multiple tasks blocked with `pid not alive` and `consecutive_failures` at retry limit.

## Diagnosis
Check worker logs: `tail -50 ~/.hermes/kanban/boards/<slug>/logs/<task_id>.log`

**Rate limit pattern:** HTTP 429 from OpenRouter, all workers using same model fail at once.

**Fallback trap:** If `fallback_model.model` == `model.default`, retries hit the same wall.

## Fix
1. Backup profile config: `cp config.yaml config.yaml.bak`
2. Switch `model.default` and `fallback_model.model` to an available model (e.g. `@preset/hermes`)
3. Reset blocked tasks: clear `consecutive_failures`, `claim_lock`, `claim_expires`, `worker_pid`, set `status='ready'`
4. Switch back after rate limit resets (check `X-RateLimit-Reset` header)

## Prevention
- fallback_model should always be a DIFFERENT model than primary
- Free-tier models exhaust quickly with parallel workers
