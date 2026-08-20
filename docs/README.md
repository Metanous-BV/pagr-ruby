# Pagr Ruby SDK — Wiki

`pagr` is the official **synchronous** Ruby client for the Pagr
document-rendering API. You give it a template ID and some JSON data; it renders
PDFs — one at a time, in batches, or as fire-and-forget background jobs with
webhook callbacks.

Maintainer-facing setup, testing, and release conventions live in
[CONTRIBUTING.md](../CONTRIBUTING.md) instead.

Questions? Join us on our [Discord server](https://discord.gg/GajJxfKXZ5).

## 30-second overview

```ruby
require "pagr"

client = Pagr::Client.new("pagr_prod_…")
result = client.render(template_id, { "Title" => "Hello" }, include_document: true)
result.document.save("out/") if result.ok?
```

## What it covers

- **Templates** — list templates & versions, read sample data, update the document-name template.
- **Rendering** — single, synchronous batch, raw-PDF streaming, and async (webhook/polling) renders.
- **Validation** — check data against a template without rendering or spending credit.
- **Documents** — list, fetch metadata, and download previously rendered PDFs.
- **Fonts & org stats** — list available fonts; read usage/credit for the organisation.

## Key facts at a glance

- **Everything is synchronous.** Calls block; there is no async abstraction to learn.
- **Auth is a bearer API key** with a `pagr_test_*` or `pagr_prod_*` prefix — the
  prefix decides test vs production mode server-side.
- **HTTP errors raise typed exceptions** (`Pagr::Error` and subclasses). The
  hierarchy is flat: `rescue Pagr::Error` catches everything, but
  `rescue Pagr::ApiError` does *not* catch a 404.
- **Business outcomes are data, not errors.** A render that fails validation or
  runs out of credit comes back as a normal result object you inspect — it does
  *not* raise.
- **Requires Ruby 3.1+** and depends only on `faraday`.

## Source layout

```
lib/
├── pagr.rb              # public entry point — requires everything below
└── pagr/
    ├── client.rb        # Pagr::Client — the API surface
    ├── http_transport.rb# Faraday wrapper: retries, backoff, error mapping
    ├── errors.rb        # Pagr::Error hierarchy + status→class table
    ├── list_options.rb  # Filter/FilterOp + canonical per-endpoint filter tables
    ├── webhook.rb       # verify_signature, parse_signed_callback (HMAC)
    ├── version.rb       # Pagr::VERSION — single source of truth
    └── models/
        ├── template.rb    # Template, TemplateVersion
        ├── render.rb      # RenderResult, BatchRenderResult, RenderJob, issues, callbacks
        ├── document.rb    # RenderDocument, PagedResult
        ├── validation.rb  # ValidationResponse
        ├── organisation.rb# OrgStats
        └── common.rb      # shared parsing helpers
examples/                # runnable scripts, one per topic (see examples/README.md)
spec/                    # RSpec suite (WebMock-stubbed HTTP — no network)
```

The authoritative reference for behaviour is
[user-guide.md](user-guide.md); `spec/exports_spec.rb` is the authoritative list
of public exports.
