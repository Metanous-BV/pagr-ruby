# Pagr Ruby SDK — User Guide

A synchronous Ruby client for the Pagr Public API (`/v1`). This guide is the
authoritative reference for the SDK's behaviour.

## Contents

1. [Setup & authentication](#1-setup--authentication)
2. [Templates & versions](#2-templates--versions)
3. [Rendering](#3-rendering)
4. [Async rendering & webhooks](#4-async-rendering--webhooks)
5. [Validation](#5-validation)
6. [Documents](#6-documents)
7. [Listing, paging, filtering](#7-listing-paging-filtering)
8. [Fonts, organisation & meta](#8-fonts-organisation--meta)
9. [Render issues](#9-render-issues)
10. [Error handling](#10-error-handling)

---

## 1. Setup & authentication

```ruby
require "pagr"

client = Pagr::Client.new(api_key, base_url: base_url, timeout: 30, max_retries: 2)
```

- `api_key` is the only required argument: `Pagr::Client.new(api_key)` targets the
  hosted API (`Pagr::Client::DEFAULT_BASE_URL`).
- `base_url` — override the Pagr Public API base; pass it only to target
  another Pagr instance.
- `api_key` — sent as `Authorization: Bearer <key>`. The prefix selects the
  mode: `pagr_test_` (watermarked, batches capped at 10 docs/request) or
  `pagr_prod_` (full render, consumes credit).
- `timeout` — per-request timeout in seconds (default 30); most render/download
  methods also accept a per-call `timeout:` override.
- `max_retries` — how many extra attempts an idempotent GET gets on a transient
  failure (HTTP 500/502/503/504, timeouts, connection errors), with capped
  exponential backoff and full jitter, honoring a `Retry-After` header when
  present. Default 2; `0` disables retries. **429 is never retried** (it
  reflects your own request volume — handle `Pagr::RateLimitError` yourself).
  **Writes (POST/PATCH) are never retried**: the API has no idempotency keys,
  so retrying could render/charge twice.

Swap the key at runtime: `client.api_key = new_key` (or `client.set_api_key(new_key)`,
the cross-SDK spelling — both do the same thing). There is no token
refresh.

The client holds no resource you must close, so there is nothing to dispose —
but that's because there's genuinely no pooled connection underneath, not
just that the client doesn't expose one. The reused Faraday `Connection`
object carries configuration only; its `net_http` adapter calls
`Net::HTTP.new` and opens a fresh socket inside `http.start do…end` for
**every** request, including retries. If your workload issues many requests
in quick succession and that per-request TCP + TLS handshake overhead
matters, that's a real cost with no built-in fix today — reaching for
`faraday-net_http_persistent` yourself is the option, at the price of also
taking on a `close`/lifecycle API this SDK doesn't otherwise need. A block
form is available if you like the scoping, but it's sugar only — it doesn't
change what gets cleaned up, because nothing needs to be:

```ruby
Pagr::Client.new(api_key, base_url: base_url) do |client|
  client.templates
end
```

## 2. Templates & versions

```ruby
page = client.templates(take: 50, sort_by: "name")     # PagedResult<Template>
template = client.template(template_id)                 # Template
versions = client.template_versions(template_id)        # PagedResult<TemplateVersion>

latest = client.template_version(template_id)           # latest published
v3     = client.template_version(template_id, 3)         # a specific version

version = client.update_document_name_template(template_id, 3, "Invoice-{{number}}")
client.update_document_name_template(template_id, 3, nil)  # clear it

url = client.preview_image_url(template_id, 3)          # String; raises NotFoundError
```

`preview_image_url` raises `Pagr::NotFoundError` when the version has no
preview image — the API answers that case with 404 (code `ImageNotFound`),
not with an empty body — so rescue it if "no preview yet" is a normal state
for your caller.

A `TemplateVersion` exposes `template_json` (the raw DSL string), `sample_data`
(parsed to a Hash — a good starting point for your own data), and
`translations` (raw JSON string or nil).

## 3. Rendering

```ruby
# Single document
result = client.render(template_id, { "customer" => "Acme" },
                       include_document: true)
result.document.save("invoice.pdf") if result.ok?

# A specific version, a language variant, without persisting
client.render(template_id, data, version: 4, language: "nl", persist: false)

# Batch (one request, many documents)
batch = client.render_batch(template_id, [data1, data2, data3])
batch.succeeded.each { |item| item.document.save("out/") }
batch.failed.each    { |item| warn item }

# Raw PDF stream — Accept: application/pdf, metadata from X-Pagr-* headers
result = client.render_pdf(template_id, data)
result.document.save("invoice.pdf") if result.ok?
```

- `include_document: true` returns the PDF inline; read it with
  `result.document.to_bytes` or `result.document.save(path)`.
- `persist: false` stores nothing, and returns the **same JSON envelope** as a
  normal render — only the values differ. `result.document.id` and `.view_url`
  are `nil` (nothing was stored, so there is nothing to reference), and the PDF
  bytes are always included inline (`document_base64` is forced on, since they
  are then the only copy), so `.to_bytes`/`.save` work regardless of
  `include_document`. Every other field is real. To receive the PDF binary
  directly instead of the JSON envelope, use `render_pdf` — the only method that
  sends `Accept: application/pdf`.
- Per document: at most 50 MB of JSON, nested at most 32 levels; a 60-second
  render budget (an overrun surfaces as a `:render_timeout` issue).
- Most render/download methods accept a per-call `timeout:` override (useful
  for a document that may approach the server's render budget):
  `client.render(template_id, data, timeout: 60)`.

`RenderResult#status` is one of `"ok"`, `"partial"`, `"failed"`,
`"insufficient_credit"`. `BatchRenderResult` is `Enumerable` over per-input
`BatchItem`s and also offers `succeeded`, `failed`, `documents`, `ok?`,
`insufficient_credit?`, and `save_all(dir)`.

**Correlation contract:** every rendered document reports its own
`document_index` — the zero-based position of the input that produced it — so it
lands on exactly that `BatchItem`. That index is the only correlation: a document
whose index is absent or out of range is dropped, never matched by list position.
Issues attach the same way via `RenderIssue#document_index` (batch-wide issues,
whose index is `nil`, attach to every item). An item left with neither a document
nor an issue gets a synthesised `:unknown`/`:error` `"not rendered"` issue.

`missing_count` is `requested_count - rendered_count` — computed by the SDK,
since that subtraction is the field's definition — and `ok?` is derived from it,
so `ok?` answers "did the whole batch render" while `failed` answers it slot by
slot.

## 4. Async rendering & webhooks

```ruby
job = client.enqueue_batch_render(template_id, data_sets, "https://you.example/cb")
# job.state == Pagr::RenderJobState::QUEUED, job.requested_count == data_sets.size

# Poll (reliable alternative to webhooks) — job_status is a single poll,
# wait_for_job is a convenience loop
status = client.wait_for_job(job.job_id, poll_interval: 2, timeout: 120)
puts status.ok? ? "done" : status.failure_reason
```

`RenderJobStatus` separates lifecycle from outcome: `state` is
`:queued`/`:pending` (non-terminal) or `:completed`/`:failed`/`:unknown`
(terminal — `status.done?` treats an unrecognised future state as terminal,
so a poll loop can never spin forever); `status` is the render outcome
(`:ok`/`:partial`/`:insufficient_credit`/`:failed`) and is `nil` while the job
is still pending. `wait_for_job`'s `timeout:` defaults to 5 minutes
(`Pagr::Client::DEFAULT_WAIT_FOR_JOB_TIMEOUT`) and raises
`Pagr::PagrTimeoutError` once it elapses before the job finishes; pass
`timeout: Float::INFINITY` to opt into unbounded polling instead.

**Cancellation.** Pass `cancelled:` — any object responding to `#call` (a
`Proc`/lambda, e.g. one that reads an `AtomicBoolean`-style flag another
thread sets) — and `wait_for_job` checks it between polls:

```ruby
cancel_requested = false
status = client.wait_for_job(job.job_id, cancelled: -> { cancel_requested })
```

Once `cancelled.call` returns truthy, `wait_for_job` returns immediately with
the most recently polled `RenderJobStatus` — not an exception. Check
`status.done?` on it: it will be `false`, so a cancelled wait can never be
mistaken for a finished one. The poll-interval sleep is chopped into small
chunks internally so cancellation is noticed promptly rather than only once
per `poll_interval`.

This does **not** abort a request already in flight: Ruby's HTTP stack here
(Faraday) is synchronous, so there is no way to interrupt a socket read
that's already underway short of `Thread#raise`, which this SDK does not
use — that's a property of the language/stack, not a bug. `cancelled:` stops
the wait between polls; `timeout:` remains the only lever that bounds an
individual poll itself.

### Callback deliveries

The server POSTs webhooks to your callback URL: one **progress** callback per
rendered document, then one **completion** callback. Every delivery carries
three headers:

| Header | Value |
|--------|-------|
| `X-Pagr-Signature` | `t=<unix seconds>,v1=<hex>[,v1=<hex>]` — HMAC-SHA256 over the raw body (see below) |
| `X-Pagr-Event` | `render.progress`, `render.completed` or `render.failed` |
| `X-Pagr-Delivery` | Stable id for this callback, **repeated across retry attempts** |

Delivery is retried: up to **5 attempts** with exponential backoff starting at
2s (2s, 4s, 8s, 16s), each attempt timing out after ~30 seconds, and deliveries
run with a concurrency of 16. Two consequences for your receiver:

- Callbacks can arrive **more than once** — deduplicate on `X-Pagr-Delivery`
  and make your handler idempotent.
- Callbacks can arrive **out of order** (both from the parallel delivery and
  because documents render in parallel) — never infer ordering from arrival;
  use `document_index` to correlate a document with its input and treat the
  completion callback as the only "everything is done" signal.

Respond quickly (do the work off the request thread) so an attempt does not hit
the 30s timeout and get retried unnecessarily.

### Verifying the signature

`X-Pagr-Signature` is how you tell a genuine callback from any POST that
reaches your listening URL — verify it before acting on a payload. Each `v1` is
lowercase-hex `HMAC-SHA256(secret, "{t}.{raw_body}")`; the timestamp is inside
the signed material, so rejecting an old `t` also rejects replays of a captured
delivery. The signing secret is per organisation: copy it from **Settings → API
keys** in the Pagr web app (it is deliberately not exposed on the `/v1` API, so
the SDK has no method to fetch it) and keep it wherever you keep credentials.

`Pagr.parse_signed_callback` is the preferred entry point — it verifies and
then parses, so an unverified payload is never decoded:

```ruby
require "sinatra"
require "pagr"

SECRET = ENV.fetch("PAGR_WEBHOOK_SECRET")

post "/pagr-callback" do
  raw_body = request.body.read      # the RAW bytes — see the warning below

  begin
    callback = Pagr.parse_signed_callback(
      raw_body, request.env["HTTP_X_PAGR_SIGNATURE"], SECRET
    )
  rescue Pagr::PagrSignatureError
    halt 400                        # not from Pagr — do not act on it
  end

  # Retries repeat the same X-Pagr-Delivery: skip work you already did.
  return 200 if already_handled?(request.env["HTTP_X_PAGR_DELIVERY"])

  case callback
  when Pagr::RenderProgress   then puts "#{callback.progress_pct.round}%"
  when Pagr::RenderCompletion then puts callback.ok? ? "complete" : callback.message
  end
  200
end
```

> **Pass the raw body bytes.** The digest covers the exact bytes POSTed. If you
> let your framework parse the JSON and then re-serialize it (`JSON.generate`,
> `params.to_json`, …) the bytes change — separators, and possibly key order —
> and the signature will never match. In Rack/Sinatra/Rails that means
> `request.body.read` (rewind it with `request.body.rewind` if something else
> reads it too), not `params`. This is the single most common cause of a
> signature that "should" match but doesn't. The SDK takes the bytes as they
> are, so a binary (`ASCII-8BIT`) body straight out of Rack and the same body
> tagged UTF-8 verify identically.

Verification raises rather than returning a boolean, so a caller who forgets to
check a return value still fails closed:

| Situation | Raised |
|-----------|--------|
| Header absent, malformed, timestamp outside the window, or no `v1` matches | `Pagr::PagrSignatureError` |
| Verified body is not JSON, or matches neither callback shape | `Pagr::PagrDecodeError` |
| `secret` is `nil`/empty (a misconfigured receiver, not a forged callback) | `ArgumentError` |

There is no "no secret configured → pass through" mode, by design.

To verify and parse separately (for example when you already hold the parsed
payload for other reasons), use `Pagr.verify_signature` — it returns `nil` on
success and raises otherwise:

```ruby
Pagr.verify_signature(raw_body, signature_header, SECRET)   # => nil, or raises
callback = Pagr.parse_callback(JSON.parse(raw_body))

# Both helpers take the same two optional keywords:
Pagr.verify_signature(raw_body, signature_header, SECRET, tolerance: 60, now: Time.now.to_f)
```

`tolerance:` is the maximum accepted drift, in seconds, between the signed `t`
and now, in **either** direction (default `Pagr::DEFAULT_SIGNATURE_TOLERANCE`,
300s — wide enough to absorb clock skew and the retry backoff; a future-dated
`t` is rejected just as an old one is). `now:` overrides the clock and exists
for tests. `Pagr::SIGNATURE_HEADER` holds the header name.

More than one `v1` appears only while a rotated-out secret is inside its 24h
grace period; verification accepts the callback when **any** `v1` matches, so
you can move to a new secret without dropping deliveries. Unknown scheme
versions (a future `v2=`) are ignored rather than treated as malformed.

### Parsing without verifying

`Pagr.parse_callback` takes an already-parsed payload `Hash`. It validates the
payload shape before dispatch and raises `Pagr::PagrDecodeError` for a payload
matching neither the progress nor the completion shape, rather than silently
mis-parsing it:

```ruby
callback = Pagr.parse_callback(json_body_hash)
```

Use it only where the request's authenticity is established some other way —
otherwise prefer `parse_signed_callback`.

## 5. Validation

Validation runs the same checks as a render but stores nothing and consumes no
credit.

```ruby
response = client.validate(template_id, data)             # single
response = client.validate(template_id, [data1, data2])   # batch

response.valid?                    # the production gate: true when no :warning/:error issue
response.errors                    # the narrower, :error-only check
response.warnings
response.issues_for(0)             # issues for document 0 (+ batch-wide issues)
```

A JSON string that encodes an array is treated as a batch.

## 6. Documents

```ruby
page = client.documents(sort_by: "renderedAt", sort_direction: "desc",
                        filters: [{ field: "environment", value: "production" }])
doc  = client.document(document_id)         # metadata only
bytes = client.download_document(document_id)  # raw PDF bytes
```

Only renders made with `persist: true` (the default) appear here. A document's
`pdf_deleted?` predicts whether `download_document` will fail with HTTP 410
(the PDF was purged by retention; the metadata remains).

## 7. Listing, paging, filtering

List methods (`templates`, `template_versions`, `documents`) share paging,
sorting, filtering and search:

```ruby
client.documents(
  skip: 0, take: 50,
  sort_by: "renderedAt", sort_direction: "desc",
  search: "invoice",
  filters: [
    { field: "environment", value: "production" },        # op defaults to :eq
    { field: "renderedAt", op: :gte, value: "2026-01-01T00:00:00Z" },
  ]
)
```

`take` defaults to 25 and is clamped to 1–200 server-side. Filters accept
plain hashes or `Pagr::Filter` objects; operators come from `Pagr::FilterOp`
(`:eq`, `:neq`, `:gt`, `:gte`, `:lt`, `:lte`, `:contains`).

Filters are validated client-side against a per-endpoint table before the
request goes out: an unknown field, or an operator that field does not support,
raises `ArgumentError`. That check exists because the server *silently ignores*
an unrecognised filter and returns the **unfiltered** result set — a typo
(`"documentNam"` for `"documentName"`) would otherwise return everything rather
than erroring.

| Method | Filterable fields | Operators |
|---|---|---|
| `#templates` | `name` | `:eq`, `:contains` |
| | `project.guid` | `:eq` |
| | `createdAt`, `updatedAt` | `:eq`, `:gt`, `:gte`, `:lt`, `:lte` |
| `#template_versions` | `versionNumber`, `publishedAt`, `createdAt`, `updatedAt` | `:eq`, `:gt`, `:gte`, `:lt`, `:lte` |
| `#documents` | `documentName` | `:eq`, `:contains` |
| | `template.guid` | `:eq` |
| | `versionNumber`, `fileSizeBytes`, `pageCount`, `renderedAt`, `createdAt`, `updatedAt` | `:eq`, `:gt`, `:gte`, `:lt`, `:lte` |
| | `environment`, `language` | `:eq`, `:neq` |

`renderDuration` can be sorted on but not filtered, and `documentType` supports
neither. The tables live in `Pagr::Filters`.

`PagedResult` is `Enumerable` and reports `total`, `skip`, `take`, and `more?`.
There is no auto-pager — walk pages yourself:

```ruby
skip = 0
loop do
  page = client.documents(skip: skip, take: 100)
  page.each { |doc| process(doc) }
  break unless page.more?
  skip += page.size
end
```

## 8. Fonts, organisation & meta

```ruby
client.fonts        # => ["Arial", "Helvetica", ...]
client.org_stats    # => OrgStats (pages/tokens used/available; -1 means unlimited)
client.status       # => true, or raises Pagr::ApiError (503)
client.version      # => deployed API version String, or nil
```

Every `OrgStats` count (`pages_used_this_period`, `pages_available`,
`included_renders_per_month`, the three `tokens_*`, `user_count`) is **`nil` when
the API omitted it**, not `0` — "the server did not report this" and "you have
used none of it" are different facts. Check for `nil` before doing arithmetic,
and remember `-1` in an "available" field means unlimited for the tier:

```ruby
stats = client.org_stats
remaining = stats.pages_available
if remaining.nil?
  # the API reported no page allowance
elsif remaining != -1 && remaining < 10
  # running low
end
```

## 9. Render issues

A `RenderIssue` has `type` and `severity` (both symbols), `description`,
`element_id`, and `document_index`. `issue.error?` is true only for `:error`
severity; `issue.blocking_production?` is true for `:warning` or `:error`.

- **Severity** — `:information`, `:warning`, `:error`. Production rendering
  blocks on `:warning` and above; test/preview blocks only on `:error`.
  Unknown/missing severities fail **closed** to `:error`. Symbols aren't
  `Comparable`, so use `Pagr::RenderIssueSeverity.at_least?`/`.blocking_production?`
  (or `issue.blocking_production?`) rather than `>=`.
- **Type** — e.g. `:missing_binding`, `:unresolved_font`, `:render_timeout`,
  `:dangerous_content`. Unrecognised types from a newer server fail **open** to
  `:unknown`, so the SDK never crashes on new server behaviour.

## 10. Error handling

```ruby
begin
  result = client.render(template_id, data)
rescue Pagr::AuthenticationError
  # 401
rescue Pagr::NotFoundError
  # 404
rescue Pagr::RateLimitError => e
  # 429 — per-organisation, sliding 60-second window; e.retry_after (seconds,
  # or nil) if the server sent one
rescue Pagr::PagrTimeoutError, Pagr::PagrConnectionError
  # the request never got a response (client-side timeout, DNS/connection
  # failure) — already retried per max_retries for idempotent GETs
rescue Pagr::Error => e
  warn "#{e.status_code} #{e.code}: #{e.message}"
end
```

Rescue `Pagr::Error` to catch everything — every failure this SDK can raise,
including transport failures (`PagrTimeoutError`, `PagrConnectionError`), an
unparseable response body (`PagrDecodeError`) and an unverifiable webhook
callback (`PagrSignatureError`), is a `Pagr::Error` subclass; you never need to
catch a raw Faraday, OpenSSL or JSON exception. The one deliberate exception is
a missing webhook signing secret, which raises `ArgumentError`: that is a bug in
your configuration, not something the network did to you, so it must not be
swallowed by a `rescue Pagr::Error` around callback handling. Remember that
validation failures and insufficient credit are **not** exceptions — check
`result.ok?` / `result.valid?`.

The hierarchy is deliberately **flat**: every class above derives directly
from `Pagr::Error`, and `Pagr::ApiError` is a *sibling* of the
status-specific classes rather than their parent. So `rescue
Pagr::ApiError` catches only the statuses that have no dedicated class (400,
410, 503, and any other 4xx/5xx) — it does **not** catch a 404 or a 401. To
handle any API error, rescue `Pagr::Error`. This mirrors the Python SDK's
`pagr.exceptions` exactly, so error handling reads the same across SDKs.
