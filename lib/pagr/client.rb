# frozen_string_literal: true

require "json"
require_relative "http_transport"
require_relative "list_options"
require_relative "models/template"
require_relative "models/render"
require_relative "models/document"
require_relative "models/validation"
require_relative "models/organisation"

module Pagr
  # A synchronous client for the Pagr Public API (+/v1+).
  #
  # Manages templates and versions, renders documents (synchronously, or via
  # fire-and-forget jobs with webhook callbacks or polling), validates data,
  # browses rendered documents and fonts, and reports organisation statistics.
  #
  #   client = Pagr::Client.new("pagr_test_...")   # hosted API
  #   client = Pagr::Client.new("pagr_test_...", base_url: "http://localhost:5110")
  #   page = client.templates(take: 50)
  #   result = client.render(template_id, { "customer" => "Acme" })
  #
  # HTTP-level failures raise a Pagr::Error subclass (401 -> AuthenticationError,
  # 404 -> NotFoundError, and so on). Business outcomes — a document that failed
  # validation, insufficient credit — come back as data on the result objects,
  # not as exceptions. All timestamps are UTC +Time+ values.
  #
  # The API key prefix selects the mode: +pagr_test_+ keys render with test
  # restrictions (watermarked output, batches capped at 10 documents per
  # request), +pagr_prod_+ keys render fully and consume credit.
  class Client
    # The transport this client sends requests through. Not part of the
    # public API surface — exposed so callers (and this SDK's own specs) can
    # tune retry/backoff behavior at runtime.
    attr_reader :http

    # The hosted Pagr Public API, used when no +base_url+ is given.
    DEFAULT_BASE_URL = "https://pagr-prd-api-public.azurewebsites.net"

    # Default overall deadline for Client#wait_for_job, in seconds (5 minutes).
    # Pass +timeout: Float::INFINITY+ for a caller that truly wants unbounded
    # polling.
    DEFAULT_WAIT_FOR_JOB_TIMEOUT = 300

    # How often, in seconds, a Client#wait_for_job poll sleep is chopped up so
    # a +cancelled:+ callable gets checked instead of sleeping out the full
    # +poll_interval+ in one go.
    WAIT_FOR_JOB_CANCEL_CHECK_INTERVAL = 0.2

    # Creates a client authenticating with +api_key+. +base_url+ defaults to the
    # hosted API (DEFAULT_BASE_URL); pass it to target another instance, e.g.
    # +base_url: "http://localhost:5110"+ for local development.
    # +timeout+ is the per-request timeout in seconds (default 30).
    # +max_retries+ is how many extra attempts an idempotent GET gets on a
    # transient failure (500/502/503/504, timeouts, connection errors);
    # default 2, 0 disables retries. Writes (POST/PATCH) are never retried.
    # Yields self when a block is given.
    def initialize(api_key, base_url: DEFAULT_BASE_URL, timeout: HttpTransport::DEFAULT_TIMEOUT,
                   max_retries: HttpTransport::DEFAULT_MAX_RETRIES)
      @http = HttpTransport.new(base_url, api_key, timeout: timeout, max_retries: max_retries)
      yield self if block_given?
    end

    # Replaces the API key used for subsequent requests. Returns self.
    def set_api_key(value)
      @http.set_api_key(value)
      self
    end

    # ── Templates ────────────────────────────────────────────────────────────

    # Lists templates available to the authenticated organisation. When
    # +project_id+ is given, lists only templates in that project.
    #
    # Sortable +sort_by+ fields: "name", "createdAt", "updatedAt" (default).
    # +filters+ accepts Filter objects or hashes (+{ field:, op:, value: }+),
    # combined with AND; op defaults to "eq".
    def templates(project_id = nil, skip: nil, take: nil, sort_by: nil,
                  sort_direction: nil, filters: nil, search: nil)
      path = project_id.nil? ? "v1/templates" : "v1/projects/#{project_id}/templates"
      params = Pagr.build_list_query(
        Pagr::Filters::TEMPLATES,
        skip: skip, take: take, sort_by: sort_by,
        sort_direction: sort_direction, filters: filters, search: search
      )
      PagedResult.from_api(@http.get(path, params).json) { |item| Template.from_api(item) }
    end

    # Fetches a single template's catalogue metadata by ID.
    def template(template_id)
      Template.from_api(@http.get("v1/templates/#{template_id}").json)
    end

    # Lists versions of a template. Sortable +sort_by+ fields: "versionNumber"
    # (default), "publishedAt", "createdAt", "updatedAt".
    def template_versions(template_id, skip: nil, take: nil, sort_by: nil,
                          sort_direction: nil, filters: nil, search: nil)
      params = Pagr.build_list_query(
        Pagr::Filters::TEMPLATE_VERSIONS,
        skip: skip, take: take, sort_by: sort_by,
        sort_direction: sort_direction, filters: filters, search: search
      )
      body = @http.get("v1/templates/#{template_id}/versions", params).json
      PagedResult.from_api(body) { |item| TemplateVersion.from_api(item) }
    end

    # Fetches a specific template version, or the latest published one. Pass a
    # version number, or +nil+ (default) / "latest" for the latest published
    # version.
    def template_version(template_id, version = nil)
      suffix = version.nil? || version == "latest" ? "latest" : version.to_s
      TemplateVersion.from_api(@http.get("v1/templates/#{template_id}/versions/#{suffix}").json)
    end

    # Updates a version's document-name template — the pattern used to name
    # documents rendered from this version. Pass +nil+ to clear it.
    def update_document_name_template(template_id, version_number, document_name_template)
      body = @http.patch_json(
        "v1/templates/#{template_id}/versions/#{version_number}/document-name-template",
        { "documentNameTemplate" => document_name_template }
      ).json
      TemplateVersion.from_api(body)
    end

    # Returns the URL of a version's preview image, or +nil+ when there is none.
    def preview_image_url(template_id, version_number)
      @http.get("v1/templates/#{template_id}/versions/#{version_number}/preview-image").json["url"]
    end

    # ── Render ─────────────────────────────────────────────────────────────

    # Renders a single document. +json_data+ is a Hash or a JSON string.
    #
    # +version+ selects a version number (default: latest published).
    # +include_document: true+ returns the PDF inline (read it with
    # +result.document.to_bytes+ / +.save+).
    #
    # This path negotiates +Accept: application/json+, for which the API always
    # returns the JSON envelope — including when +persist: false+. Nothing is
    # stored then, so +result.document.id+ and +.view_url+ are +nil+, and the
    # base64 bytes are forced on (they are the only copy), which makes
    # +.to_bytes+/+.save+ work regardless of +include_document+. Every other
    # field is real. To stream the raw PDF binary instead of the JSON envelope,
    # use Client#render_pdf — the only method that sends
    # +Accept: application/pdf+.
    #
    # +timeout+ overrides the client's configured timeout for this call only;
    # use a larger value for a document that may approach the server's
    # render budget.
    #
    # Returns a RenderResult. Reasons a document did not render are reported as
    # RenderIssues in +result.issues+, not exceptions.
    def render(template_id, json_data, version: nil, include_document: false,
               language: nil, persist: true, timeout: nil)
      response = @http.post_json(
        render_path(template_id, version),
        { "documents" => [to_payload(json_data)], "includeDocument" => include_document },
        { language: language, persist: persist },
        timeout: timeout
      )
      RenderResult.from_api(response.json)
    end

    # Renders a single document and streams the raw PDF back.
    #
    # This is the opt-in +Accept: application/pdf+ path: instead of the JSON
    # envelope Client#render returns, the API streams the PDF binary
    # directly, carrying the document metadata in +X-Pagr-*+ response
    # headers. Use it when you want the bytes without base64-decoding a JSON
    # field.
    #
    # Only single-document renders are supported — this always sends exactly
    # one document.
    #
    # Returns a PdfRenderResult. On a clean render +result.ok?+ is true and
    # +result.document+ is a PdfDocument (+.to_bytes+ / +.save+). When the
    # document is blocked or fails to render there is no PDF to stream, so
    # +result.ok?+ is false and the reasons are in +result.issues+ /
    # +result.status+ — a business outcome, not an exception.
    def render_pdf(template_id, json_data, version: nil, language: nil,
                   persist: true, timeout: nil)
      response = @http.post_json(
        render_path(template_id, version),
        { "documents" => [to_payload(json_data)] },
        { language: language, persist: persist },
        headers: { "Accept" => "application/pdf" },
        non_raising_statuses: [422],
        timeout: timeout
      )
      if response.status == 422
        PdfRenderResult.from_error_envelope(response.json)
      else
        PdfRenderResult.new(
          document: PdfDocument.from_response(response.headers, response.body),
          status: "ok"
        )
      end
    end

    # Renders multiple documents in a single request. +json_data_sets+ is an
    # array of Hashes or JSON strings. Test-mode keys are limited to 10
    # documents per request. Returns a BatchRenderResult correlating each input
    # to its document — matched via the +document_index+ the API reports for
    # each — or the issues that prevented it.
    def render_batch(template_id, json_data_sets, version: nil,
                     include_document: false, language: nil, persist: true,
                     timeout: nil)
      inputs = json_data_sets.map { |data| to_payload(data) }
      response = @http.post_json(
        render_path(template_id, version),
        { "documents" => inputs, "includeDocument" => include_document },
        { language: language, persist: persist },
        timeout: timeout
      )
      BatchRenderResult.from_api(response.json, inputs: inputs)
    end

    # Enqueues a fire-and-forget batch render. Returns immediately with a
    # RenderJob (state :queued); the server renders in the background and
    # POSTs webhooks to +callback_url+ (one progress callback per rendered
    # document, one completion callback at the end — parse them with
    # Pagr.parse_callback). Poll Client#job_status (or Client#wait_for_job)
    # as a reliable alternative.
    def enqueue_batch_render(template_id, json_data_sets, callback_url,
                             version: nil, include_document: false,
                             language: nil, persist: true, timeout: nil)
      response = @http.post_json(
        render_path(template_id, version, "/async"),
        {
          "documents" => json_data_sets.map { |data| to_payload(data) },
          "callbackUrl" => callback_url,
          "includeDocument" => include_document,
        },
        { language: language, persist: persist },
        timeout: timeout
      )
      RenderJob.from_api(response.json)
    end

    # Polls the status of an async render job. Returns a RenderJobStatus; poll
    # on an interval until +status.done?+ (or use Client#wait_for_job), then
    # check +status.ok?+ / +status.failure_reason+.
    def job_status(job_id)
      RenderJobStatus.from_api(@http.get("v1/render/jobs/#{job_id}").json)
    end

    # Polls Client#job_status until the job reaches a terminal state — a
    # convenience wrapper over a hand-rolled "while not status.done?" loop.
    # Because #done? treats an unrecognised state as terminal (fail-open),
    # this never spins forever on a server state the SDK does not know about.
    #
    # +poll_interval+ is how many seconds to wait between polls (default 2.0).
    # +timeout+ is the overall deadline in seconds across all polls; defaults
    # to DEFAULT_WAIT_FOR_JOB_TIMEOUT (5 minutes). An explicit +timeout: nil+
    # means the same as omitting it, so a caller can pass through whatever
    # their own config holds without a guard. Pass
    # +timeout: Float::INFINITY+ to opt out and poll indefinitely.
    #
    # +cancelled+ is an optional zero-arg callable (a +Proc+/+lambda+
    # responding to +#call+) checked between poll sleeps. Once it returns
    # truthy, +wait_for_job+ returns the most recently polled
    # RenderJobStatus — note that +status.done?+ will be +false+ on it, so a
    # cancelled wait cannot be mistaken for a finished one. This is not an
    # abort of any in-flight HTTP call: Ruby's Faraday stack is synchronous,
    # so there is no way to interrupt a socket read already in progress short
    # of +Thread#raise+, which this SDK does not use. What +cancelled+ *does*
    # do is stop the wait promptly between polls — the poll-interval sleep is
    # chopped into WAIT_FOR_JOB_CANCEL_CHECK_INTERVAL-sized chunks so the
    # predicate is noticed well before the next full +poll_interval+ elapses,
    # rather than only once per interval.
    #
    # Raises PagrTimeoutError if +timeout+ elapses before the job finishes.
    # (+cancelled+ firing is not a timeout and never raises.)
    def wait_for_job(job_id, poll_interval: 2.0, timeout: nil, cancelled: nil)
      timeout = DEFAULT_WAIT_FOR_JOB_TIMEOUT if timeout.nil?
      deadline = timeout == Float::INFINITY ? nil : monotonic_now + timeout
      status = nil
      loop do
        status = job_status(job_id)
        return status if status.done?

        if deadline
          remaining = deadline - monotonic_now
          raise Pagr::PagrTimeoutError, "job #{job_id} did not finish within #{timeout}s" if remaining <= 0

          wait_seconds = [poll_interval, remaining].min
        else
          wait_seconds = poll_interval
        end

        return status unless sleep_or_cancel(wait_seconds, cancelled)
      end
    end

    # ── Validate ─────────────────────────────────────────────────────────────

    # Validates document data against a template without rendering (consumes no
    # credit). +json_data+ is a single document (Hash/JSON string) or an array
    # of them; a JSON string encoding an array is treated as a batch. Returns a
    # ValidationResponse — +result.valid?+ is true when no issue has +:error+
    # severity.
    def validate(template_id, json_data, version: nil)
      payload = json_data.is_a?(Array) ? json_data : to_payload(json_data)
      documents = payload.is_a?(Array) ? payload.map { |d| to_payload(d) } : [payload]
      body = @http.post_json(
        render_path(template_id, version, "/validate"),
        { "documents" => documents }
      ).json
      ValidationResponse.from_api(body)
    end

    # ── Documents ──────────────────────────────────────────────────────────

    # Lists rendered documents (metadata only) for the authenticated
    # organisation. Only renders made with +persist: true+ appear here. Sortable
    # +sort_by+ fields include "renderedAt" (default), "documentName",
    # "pageCount", "environment"; filterable fields include "environment" and
    # "language".
    def documents(skip: nil, take: nil, sort_by: nil, sort_direction: nil,
                  filters: nil, search: nil)
      params = Pagr.build_list_query(
        Pagr::Filters::DOCUMENTS,
        skip: skip, take: take, sort_by: sort_by,
        sort_direction: sort_direction, filters: filters, search: search
      )
      PagedResult.from_api(@http.get("v1/documents", params).json) { |item| RenderDocument.from_api(item) }
    end

    # Fetches a single rendered document's metadata by ID (no PDF bytes; use
    # Client#download_document for the file).
    def document(document_id)
      RenderDocument.from_api(@http.get("v1/documents/#{document_id}").json)
    end

    # Downloads a rendered document's PDF bytes (a binary String). Raises
    # ApiError (HTTP 410, code "PdfDeleted") when the stored PDF has been purged
    # by retention. +timeout+ overrides the client's configured timeout for
    # this call only.
    def download_document(document_id, timeout: nil)
      @http.get("v1/documents/#{document_id}/file", timeout: timeout).body
    end

    # ── Fonts / Organisation / Meta ──────────────────────────────────────────

    # Lists the font family names available for rendering.
    def fonts
      @http.get("v1/fonts").json.to_a
    end

    # Fetches usage and credit statistics for the current billing period.
    def org_stats
      OrgStats.from_api(@http.get("v1/organisation/stats").json)
    end

    # Checks API health. Returns +true+ when the service reports healthy; raises
    # ApiError (503) otherwise.
    def status
      @http.get("v1/meta/status")
      true
    end

    # Returns the deployed API version string (distinct from the Pagr::VERSION
    # gem constant), or +nil+.
    def version
      @http.get("v1/meta/version").json["version"]
    end

    private

    # Builds a render endpoint path. +version+ of +nil+ targets the latest
    # published version; otherwise the specific version. +suffix+ appends
    # "/async" or "/validate".
    def render_path(template_id, version, suffix = "")
      base =
        if version.nil?
          "v1/render/#{template_id}"
        else
          "v1/render/#{template_id}/versions/#{version}"
        end
      base + suffix
    end

    # Normalises a caller-supplied document (Hash or JSON string) into plain
    # data for transport.
    def to_payload(data)
      data.is_a?(String) ? JSON.parse(data) : data
    end

    # A monotonic clock reading in seconds, immune to wall-clock adjustments —
    # used for Client#wait_for_job's deadline arithmetic.
    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Sleeps up to +duration+ seconds for Client#wait_for_job, checking
    # +cancelled+ along the way. With no +cancelled+ callable this is a
    # single bare +sleep+ — unchanged from before +cancelled:+ existed.
    # With one, the sleep is chopped into WAIT_FOR_JOB_CANCEL_CHECK_INTERVAL
    # chunks so cancellation is noticed promptly instead of waiting out the
    # whole interval. Returns +false+ (and stops sleeping) the moment
    # +cancelled.call+ is truthy, +true+ once the full duration has elapsed.
    def sleep_or_cancel(duration, cancelled)
      unless cancelled
        sleep(duration)
        return true
      end

      remaining = duration
      while remaining > 0
        return false if cancelled.call

        chunk = [WAIT_FOR_JOB_CANCEL_CHECK_INTERVAL, remaining].min
        sleep(chunk)
        remaining -= chunk
      end
      !cancelled.call
    end
  end
end
