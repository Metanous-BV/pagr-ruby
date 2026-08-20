# Contributing

Instructions for people **maintaining** this SDK. If you only want to *use* it,
read the [User Guide](docs/user-guide.md) instead.

## Development setup

From the repository root:

```bash
bundle install
```

Requires **Ruby 3.1 or later**. The library's only runtime dependency is
`faraday` (~> 2.0); `rake`, `rspec` and `webmock` are development dependencies
declared in the `Gemfile` and never reach consumers.

`Gemfile.lock` is deliberately **not** committed and is gitignored. A library
must not pin its consumers' dependency resolution, and CI should be free to
resolve against current gems.

### Running tests

```bash
bundle exec rspec        # or: bundle exec rake
```

No live API is needed — the suite is fully self-contained.

## Testing conventions

- **Mock at the HTTP layer** with WebMock (see `spec/support/http_helpers.rb`),
  never by stubbing or subclassing `Pagr::Client`. This exercises path
  building, query-parameter cleaning and error mapping for real.
- **Assert the URL**, not just the parsed result — a route regression is easy to
  miss otherwise. `spec/spec_helper.rb` defines the stub host; it is a mock
  target, not a suggestion that anyone point the client at localhost.
- **Cover both paths:** the happy JSON response *and* at least one error status
  mapping to its typed exception. Every `Pagr::Error` subclass should have a
  test that provokes it.
- **Binary/PDF branches get their own test.** Streaming bytes, `X-Pagr-*`
  header metadata and `#save` path handling do not share a code path with the
  JSON branch.
- **Business outcomes are not exceptions.** A failed validation or insufficient
  credit comes back as data on the result object; assert that it does *not*
  raise.
- Model specs should assert camelCase→snake_case mapping, fail-open enum
  behaviour (an unknown value becomes `Unknown`, never an exception) and default
  handling.
- `spec/exports_spec.rb` is the authoritative list of public exports. Adding a
  class to the public surface means adding it there.

`examples/` hits a **live** API and needs a real API key. The examples are run
manually only and are never part of an automated test run — CI does not execute
them.

## Build & release

```bash
bundle exec rspec
gem build pagr.gemspec
```

Inspect the built gem before pushing it:

```bash
tar -xOf pagr-<version>.gem metadata.gz | gunzip | head -40
tar -tf pagr-<version>.gem
```

It must contain `lib/`, `docs/`, `examples/`, `README.md`, `LICENSE`,
`CHANGELOG.md` and `CONTRIBUTING.md`, and must **not** contain `spec/`, any
`.pdf`, or a `.env`.

Keep the links in `README.md` **absolute** (`https://github.com/Metanous-BV/pagr-ruby/blob/main/...`):
relative links resolve on GitHub but are dead on the RubyGems page, which
renders the same README.

Release checklist:

1. Bump `Pagr::VERSION` in `lib/pagr/version.rb` (SemVer). The gemspec reads
   that constant — it is the single source of truth.
2. Update `README.md` and the [User Guide](docs/user-guide.md) if the surface
   changed.
3. Add a `CHANGELOG.md` entry.
4. `bundle exec rspec` green on the full CI matrix — Ruby 3.1–3.4 on both Linux
   and Windows. The OS matrix matters: `#save` / `#save_all` do real filesystem
   path work.
5. `gem build`, then inspect the `.gem` as above.
6. Tag the release, then `gem push pagr-<version>.gem`.

**Versioning policy.** The SDK follows SemVer: a breaking change to the public
surface (a removed or renamed export, a changed method signature or return type,
or a behavioural change consumers rely on) bumps the **major** version; additive,
backward-compatible changes bump **minor**; fixes bump **patch**. Record
consumer-visible changes in `CHANGELOG.md` per release.

Two specifics worth naming:

- **Changing `Pagr::Client::DEFAULT_BASE_URL` is a major bump.** Consumers who
  never pass `base_url:` would silently start talking to a different host.
- **Raising `required_ruby_version` is a major bump.** Dropping a Ruby version
  breaks `bundle install` for anyone still on it.

## Getting help

Working on the SDK and stuck? Join us on our
[Discord server](https://discord.gg/GajJxfKXZ5) — Pagr engineers are there.
Bugs and feature requests belong in
[GitHub issues](https://github.com/Metanous-BV/pagr-ruby/issues).
