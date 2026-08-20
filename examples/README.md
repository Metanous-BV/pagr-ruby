# Examples

Runnable scripts demonstrating each part of the SDK. They read configuration
from the environment — never commit real keys.

## Setup

```bash
export PAGR_BASE_URL=http://localhost:5110     # optional; this is the default
export PAGR_API_KEY=pagr_test_...              # required
```

Run one with the gem's `lib` on the load path:

```bash
ruby -Ilib examples/getting_started.rb
```

## Scripts

| Script | Shows |
|--------|-------|
| `getting_started.rb` | Connect, health check, list templates |
| `templates.rb` | Browse templates and versions; sort & filter |
| `render_single.rb` | Render one document, save the PDF |
| `render_batch.rb` | Render many in one request, save successes |
| `batch_async.rb` | Enqueue an async job and poll to completion |
| `validate.rb` | Validate data without rendering |
| `documents.rb` | Browse and download persisted documents |
| `account.rb` | Organisation usage/credit and fonts |
| `error_handling.rb` | Exceptions vs. business outcomes |
