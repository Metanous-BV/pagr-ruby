# frozen_string_literal: true

require "json"
require_relative "common"

module Pagr
  # Severity of a RenderIssue, as a symbol: +:information+, +:warning+ or
  # +:error+. Ordered by how much it blocks rendering: production blocks any
  # issue +>= :warning+; test/preview blocks only +:error+.
  module RenderIssueSeverity
    INFORMATION = :information
    WARNING = :warning
    ERROR = :error

    # Symbol => wire (API) string.
    WIRE = {
      INFORMATION => "Information",
      WARNING => "Warning",
      ERROR => "Error",
    }.freeze

    # Rank used for ordering comparisons (higher = more severe). Severities
    # are plain symbols, not Comparable, so +:warning >= :error+ would raise
    # +NoMethodError+ — use #at_least? (or RenderIssue#blocking_production?)
    # instead.
    RANK = {
      INFORMATION => 0,
      WARNING => 1,
      ERROR => 2,
    }.freeze

    # Parses the API's string value. Unknown or missing values fail closed to
    # +:error+, so a new server severity never renders a blocking issue
    # harmless.
    def self.from_api(value)
      return ERROR if value.nil?

      normalised = value.to_s.downcase
      WIRE.each { |sym, wire| return sym if wire.downcase == normalised }
      ERROR
    end

    # The API string for a severity symbol.
    def self.to_wire(symbol)
      WIRE[symbol]
    end

    # True when +severity+ is +other+ or more severe, per the explicit rank
    # (+:information < :warning < :error+).
    def self.at_least?(severity, other)
      RANK[severity] >= RANK[other]
    end

    # True when an issue of this severity blocks a production render (i.e.
    # it is +:warning+ or +:error+).
    def self.blocking_production?(severity)
      at_least?(severity, WARNING)
    end
  end

  # Category of a RenderIssue, as a symbol mirroring the API's RenderIssueType.
  # +:unknown+ is a client-side fallback (not a server value): unknown types
  # parse to it rather than raising, so new server behaviour never crashes an
  # older client.
  module RenderIssueType
    INVALID_JSON = :invalid_json
    SCHEMA_INVALID = :schema_invalid
    DANGEROUS_CONTENT = :dangerous_content
    MISSING_BINDING = :missing_binding
    UNRESOLVED_IMAGE = :unresolved_image
    UNRESOLVED_FONT = :unresolved_font
    INVALID_COLOR = :invalid_color
    INVALID_CONDITION = :invalid_condition
    DATA_SOURCE_NOT_ENUMERABLE = :data_source_not_enumerable
    INVALID_CHART_CONFIG = :invalid_chart_config
    INVALID_PAGE_BACKGROUND = :invalid_page_background
    BINDING_FAILED_AT_RENDER = :binding_failed_at_render
    RENDER_TIMEOUT = :render_timeout
    RENDER_LAYOUT_DEGRADED = :render_layout_degraded
    INVALID_LAYOUT = :invalid_layout
    UNFORMATTED_VALUE = :unformatted_value
    UNKNOWN = :unknown

    # Symbol => wire (API) string.
    WIRE = {
      INVALID_JSON => "InvalidJson",
      SCHEMA_INVALID => "SchemaInvalid",
      DANGEROUS_CONTENT => "DangerousContent",
      MISSING_BINDING => "MissingBinding",
      UNRESOLVED_IMAGE => "UnresolvedImage",
      UNRESOLVED_FONT => "UnresolvedFont",
      INVALID_COLOR => "InvalidColor",
      INVALID_CONDITION => "InvalidCondition",
      DATA_SOURCE_NOT_ENUMERABLE => "DataSourceNotEnumerable",
      INVALID_CHART_CONFIG => "InvalidChartConfig",
      INVALID_PAGE_BACKGROUND => "InvalidPageBackground",
      BINDING_FAILED_AT_RENDER => "BindingFailedAtRender",
      RENDER_TIMEOUT => "RenderTimeout",
      RENDER_LAYOUT_DEGRADED => "RenderLayoutDegraded",
      INVALID_LAYOUT => "InvalidLayout",
      UNFORMATTED_VALUE => "UnformattedValue",
      UNKNOWN => "Unknown",
    }.freeze

    # Parses the API's string value. Unknown or missing values fail open to
    # +:unknown+ so unrecognised server types never raise.
    def self.from_api(value)
      return UNKNOWN if value.nil?

      normalised = value.to_s.downcase
      WIRE.each { |sym, wire| return sym if wire.downcase == normalised }
      UNKNOWN
    end

    # The API string for a type symbol.
    def self.to_wire(symbol)
      WIRE[symbol]
    end
  end

  # Lifecycle state of an async render job, as a symbol: +:queued+ / +:pending+
  # (non-terminal — the job hasn't stopped advancing), +:completed+ (documents
  # produced, including partial/credit-stopped runs) or +:failed+ (produced
  # nothing).
  #
  # +:unknown+ is a client-side fail-open fallback (not a server value): an
  # unrecognised state parses to it rather than raising, and #terminal? treats
  # it as terminal so a new server state can never trap a polling loop in an
  # infinite wait.
  module RenderJobState
    QUEUED = :queued
    PENDING = :pending
    COMPLETED = :completed
    FAILED = :failed
    UNKNOWN = :unknown

    # Symbol => wire (API) string.
    WIRE = {
      QUEUED => "queued",
      PENDING => "pending",
      COMPLETED => "completed",
      FAILED => "failed",
      UNKNOWN => "unknown",
    }.freeze

    NON_TERMINAL = [QUEUED, PENDING].freeze

    # Parses the API's string value. Unknown or missing values fail open to
    # +:unknown+ so unrecognised server states never raise.
    def self.from_api(value)
      return UNKNOWN if value.nil?

      normalised = value.to_s.downcase
      WIRE.each { |sym, wire| return sym if wire.downcase == normalised }
      UNKNOWN
    end

    # The API string for a state symbol.
    def self.to_wire(symbol)
      WIRE[symbol]
    end

    # True once the job has stopped advancing. +:unknown+ counts as terminal
    # (fail-open) so an unrecognised state ends a polling loop rather than
    # spinning forever.
    def self.terminal?(symbol)
      !NON_TERMINAL.include?(symbol)
    end
  end

  # Render outcome of a job or webhook callback, as a symbol mirroring the
  # sync render envelope's status vocabulary: +:ok+, +:partial+, +:failed+ or
  # +:insufficient_credit+. +nil+ (not this module) is used while a job is
  # still pending; once decided it is one of these.
  #
  # +:unknown+ is a client-side fail-open fallback for an unrecognised server
  # value, so new outcomes never crash an older client.
  module RenderOutcome
    OK = :ok
    PARTIAL = :partial
    FAILED = :failed
    INSUFFICIENT_CREDIT = :insufficient_credit
    UNKNOWN = :unknown

    # Symbol => wire (API) string.
    WIRE = {
      OK => "ok",
      PARTIAL => "partial",
      FAILED => "failed",
      INSUFFICIENT_CREDIT => "insufficient_credit",
      UNKNOWN => "unknown",
    }.freeze

    # Parses the API's string value. Unknown or missing values fail open to
    # +:unknown+ so unrecognised server outcomes never raise.
    def self.from_api(value)
      return UNKNOWN if value.nil?

      normalised = value.to_s.downcase
      WIRE.each { |sym, wire| return sym if wire.downcase == normalised }
      UNKNOWN
    end

    # The API string for an outcome symbol.
    def self.to_wire(symbol)
      WIRE[symbol]
    end
  end

  # A single render or validation issue. +type+ carries the category and
  # +severity+ the blocking-ness. +document_index+ is the zero-based position of
  # the document it pertains to in a batch, or +nil+ for single-document
  # operations and batch-wide issues.
  class RenderIssue
    attr_reader :type, :severity, :description, :element_id, :document_index

    def initialize(type:, severity:, description: "", element_id: nil,
                   document_index: nil)
      @type = type
      @severity = severity
      @description = description
      @element_id = element_id
      @document_index = document_index
    end

    # True when this issue has +:error+ severity (blocks the document).
    def error?
      severity == RenderIssueSeverity::ERROR
    end

    # True when this issue blocks a production render (+:warning+ or +:error+).
    def blocking_production?
      RenderIssueSeverity.blocking_production?(severity)
    end

    def self.from_api(data)
      new(
        type: RenderIssueType.from_api(data["type"]),
        severity: RenderIssueSeverity.from_api(data["severity"]),
        description: data.fetch("description", ""),
        element_id: data["elementId"],
        document_index: data["documentIndex"]
      )
    end

    def to_s
      location = element_id ? " [#{element_id}]" : ""
      "#{RenderIssueSeverity.to_wire(severity)}: #{RenderIssueType.to_wire(type)}#{location} — #{description}"
    end
  end

  # A document produced by a render call. Returned inside RenderResult /
  # BatchRenderResult and in async-render progress webhooks.
  #
  # +document_base64+ carries the PDF bytes only when rendered with
  # +include_document: true+; decode it with #to_bytes or write it with #save.
  #
  # +document_index+ is this document's zero-based position in the render
  # request's data array, so it can be correlated with the input that produced
  # it; +nil+ outside a render response (e.g. the document-listing endpoints,
  # where there is no request to index into).
  #
  # +language+ is the language variant the document was rendered in, for
  # templates with translations; +nil+ when the template has no translations or
  # the render did not specify one.
  class RenderedDocument
    attr_reader :id, :document_name, :template_id, :version_number, :environment,
                :file_size_bytes, :page_count, :rendered_at, :render_duration,
                :view_url, :document_type, :document_base64, :language,
                :document_index

    def initialize(id:, document_name:, template_id:, version_number:,
                   environment:, file_size_bytes:, page_count:, rendered_at:,
                   render_duration:, view_url:, document_type:,
                   document_base64: nil, language: nil, document_index: nil)
      @id = id
      @document_name = document_name
      @template_id = template_id
      @version_number = version_number
      @environment = environment
      @file_size_bytes = file_size_bytes
      @page_count = page_count
      @rendered_at = rendered_at
      @render_duration = render_duration
      @view_url = view_url
      @document_type = document_type
      @document_base64 = document_base64
      @language = language
      @document_index = document_index
    end

    def self.from_api(data)
      new(
        id: data["id"],
        document_name: data["documentName"],
        template_id: data["templateId"],
        version_number: data["versionNumber"],
        environment: data["environment"],
        file_size_bytes: data["fileSizeBytes"],
        page_count: data["pageCount"],
        rendered_at: Common.parse_time(data["renderedAt"]),
        render_duration: data["renderDuration"],
        view_url: data["viewUrl"],
        document_type: data["documentType"],
        document_base64: data["documentBase64"],
        language: data["language"],
        document_index: data["documentIndex"]
      )
    end

    # The decoded document bytes (a binary String). Only available when the
    # document was rendered with +include_document: true+.
    def to_bytes
      raise Pagr::Error, "This document has no inline content. Render with " \
                         "include_document: true to receive the document bytes." if document_base64.nil?

      document_base64.unpack1("m")
    end

    # Writes the document to disk. When +path+ is an existing directory, a
    # sanitised form of +document_name+ is used as the filename inside it
    # (directory components, drive letters and traversal are stripped —
    # +document_name+ is server-echoed data, not a trusted path segment),
    # with a ".pdf" extension appended when it doesn't already have one.
    # Returns the path written.
    def save(path)
      if File.directory?(path)
        filename = Common.safe_filename(document_name)
        filename += ".pdf" unless filename.downcase.end_with?(".pdf")
        path = File.join(path, filename)
      end
      File.binwrite(path, to_bytes)
      path
    end

    def to_s
      "RenderedDocument #{document_name} (#{id})"
    end
  end

  # A single document returned as a raw PDF stream by Client#render_pdf.
  #
  # Unlike RenderedDocument (built from the JSON envelope), this carries only
  # what the raw-PDF response actually provides — the bytes plus the metadata
  # the server puts in +X-Pagr-*+ headers. Fields the headers do not carry
  # (template id, version, environment, timestamp, type, language) are
  # deliberately absent rather than fabricated.
  #
  # +document_id+ and +view_url+ are +nil+ when the render was not persisted
  # (+persist: false+).
  class PdfDocument
    attr_reader :document_name, :content, :document_id, :page_count,
                :render_duration, :view_url, :issue_count

    def initialize(document_name:, content:, document_id: nil, page_count: 0,
                   render_duration: 0.0, view_url: nil, issue_count: 0)
      @document_name = document_name
      @content = content
      @document_id = document_id
      @page_count = page_count
      @render_duration = render_duration
      @view_url = view_url
      @issue_count = issue_count
    end

    # Builds a PdfDocument from a raw application/pdf response, reading the
    # document metadata out of its X-Pagr-* headers and the name from
    # Content-Disposition. +headers+ is a case-insensitive header hash (see
    # RawResponse#headers); +content+ is the raw response body.
    def self.from_response(headers, content)
      doc_id = headers["X-Pagr-Document-Id"]
      new(
        document_name: filename_from_content_disposition(headers["Content-Disposition"]),
        content: content,
        document_id: doc_id.to_s.empty? ? nil : doc_id,
        page_count: headers["X-Pagr-Page-Count"].to_i,
        render_duration: headers["X-Pagr-Render-Duration-Ms"].to_f,
        view_url: headers["X-Pagr-View-Url"],
        issue_count: headers["X-Pagr-Issue-Count"].to_i
      )
    end

    # Extracts a filename from a Content-Disposition header value (the plain
    # filename= parameter, quotes stripped, and a trailing ".pdf" stripped
    # case-insensitively), falling back to "document" when absent,
    # unparseable, or empty after stripping. Deliberately does not match the
    # RFC 6266 extended filename*= form — Python's reference implementation
    # is a literal "filename=" substring search that can't match it either
    # (the "=" there is preceded by "*"), and every SDK must replicate that
    # exact behavior rather than the fuller extended-parameter parsing.
    def self.filename_from_content_disposition(header)
      return "document" if header.nil?

      match = header.match(/filename=\s*"?([^";]+)"?/i)
      return "document" if match.nil?

      name = match[1].sub(/\A"+/, "").sub(/"+\z/, "").strip
      name = name.sub(/\.pdf\z/i, "")
      name.empty? ? "document" : name
    end
    private_class_method :filename_from_content_disposition

    # The raw PDF bytes.
    def to_bytes
      content
    end

    # Writes the document to disk. See RenderedDocument#save — the same
    # sanitisation rules apply. Returns the path written.
    def save(path)
      if File.directory?(path)
        filename = Common.safe_filename(document_name)
        filename += ".pdf" unless filename.downcase.end_with?(".pdf")
        path = File.join(path, filename)
      end
      File.binwrite(path, content)
      path
    end

    def to_s
      "PdfDocument #{document_name} (#{page_count} page(s))"
    end
  end

  # Result of a Client#render_pdf call.
  #
  # +document+ is the rendered PdfDocument on success, or +nil+ when the
  # render was blocked/failed — inspect +issues+ and +status+ for why (a
  # business outcome, not an exception). +status+ is one of "ok", "partial",
  # "failed" or "insufficient_credit".
  class PdfRenderResult
    attr_reader :document, :status, :message, :issues

    def initialize(document:, status:, message: nil, issues: [])
      @document = document
      @status = status
      @message = message
      @issues = issues
    end

    # True when a rendered PDF came back.
    def ok?
      !document.nil?
    end

    # True when the render was blocked because the organisation is out of
    # credit.
    def insufficient_credit?
      status == "insufficient_credit"
    end

    # Builds a failed result from the JSON envelope the API returns (with
    # HTTP 422) when there is no PDF to stream.
    def self.from_error_envelope(data)
      new(
        document: nil,
        status: data.fetch("status", "failed"),
        message: data["message"],
        issues: (data["issues"] || []).map { |i| RenderIssue.from_api(i) }
      )
    end

    def to_s
      return document.to_s if ok?

      errors = issues.select(&:error?).map(&:description)
      reason = errors.empty? ? (message || status || "not rendered") : errors.join("; ")
      "PdfRenderResult FAILED — #{reason}"
    end
  end

  # Result of a single-document render.
  #
  # +status+ is one of "ok", "partial", "failed" or "insufficient_credit".
  # +document+ is +nil+ when the document did not render — inspect #ok?,
  # +issues+ and +status+ to find out why. Business failures (validation,
  # insufficient credit) are outcomes here, not exceptions.
  class RenderResult
    attr_reader :document, :status, :rendered_count, :requested_count,
                :missing_count, :message, :issues

    def initialize(document:, status:, rendered_count: 0, requested_count: 0,
                   missing_count: 0, message: nil, issues: [])
      @document = document
      @status = status
      @rendered_count = rendered_count
      @requested_count = requested_count
      @missing_count = missing_count
      @message = message
      @issues = issues
    end

    # True when a rendered document came back.
    def ok?
      !document.nil?
    end

    # True when the render was blocked because the organisation is out of
    # credit.
    def insufficient_credit?
      status == "insufficient_credit"
    end

    def self.from_api(data)
      docs = data["documents"] || []
      document = docs.empty? ? nil : RenderedDocument.from_api(docs[0])
      issues = (data["issues"] || []).map { |i| RenderIssue.from_api(i) }

      new(
        document: document,
        status: data.fetch("status", "ok"),
        rendered_count: data.fetch("renderedCount", document ? 1 : 0),
        requested_count: data.fetch("requestedCount", 1),
        missing_count: data.fetch("missingCount", document ? 0 : 1),
        message: data["message"],
        issues: issues
      )
    end

    def to_s
      return document.to_s if ok?

      errors = issues.select(&:error?).map(&:description)
      reason = errors.empty? ? (message || status || "not rendered") : errors.join("; ")
      "RenderResult FAILED — #{reason}"
    end
  end

  # The outcome of a single document within a batch render. Correlates one
  # submitted input to its rendered document or the issues that prevented it
  # from rendering: the input is attached by its position in the submitted
  # array, while the document and issues are matched via the +document_index+
  # the API reports for each.
  class BatchItem
    attr_reader :index, :input
    attr_accessor :document, :issues

    def initialize(index:, input: nil, document: nil, issues: [])
      @index = index
      @input = input
      @document = document
      @issues = issues
    end

    # True when this input produced a rendered document.
    def ok?
      !document.nil?
    end

    def to_s
      if ok?
        "[#{index}] OK — #{document.document_name}"
      else
        errors = issues.select(&:error?).map(&:description)
        "[#{index}] FAILED — #{errors.empty? ? 'not rendered' : errors.join('; ')}"
      end
    end
  end

  # Result of a synchronous batch render. Enumerable over per-input BatchItems
  # (+each+, +[]+, +size+, plus everything Enumerable gives you).
  #
  # +status+ is one of "ok", "partial", "failed" or "insufficient_credit".
  #
  # +missing_count+ is +requested_count - rendered_count+ — that subtraction
  # *is* its definition, so it is computed rather than read from the response,
  # and +ok?+ is derived from it.
  class BatchRenderResult
    include Enumerable

    attr_reader :items, :status, :message, :requested_count, :rendered_count,
                :missing_count

    def initialize(items:, status:, message:, requested_count:, rendered_count:,
                   missing_count:)
      @items = items
      @status = status
      @message = message
      @requested_count = requested_count
      @rendered_count = rendered_count
      @missing_count = missing_count
    end

    def each(&block)
      items.each(&block)
    end

    def [](index)
      items[index]
    end

    def size
      items.size
    end
    alias length size

    # The items that produced a rendered document.
    def succeeded
      items.select(&:ok?)
    end

    # The items that did not render; inspect each item's +issues+.
    def failed
      items.reject(&:ok?)
    end

    # All successfully rendered documents.
    def documents
      items.map(&:document).compact
    end

    # True when the batch was cut short because the organisation ran out of
    # credit.
    def insufficient_credit?
      status == "insufficient_credit"
    end

    # True when every requested document rendered and credit sufficed.
    def ok?
      missing_count.zero? && !insufficient_credit?
    end

    # Writes every rendered document that carries inline content to +directory+
    # (created if it does not exist). Returns the paths written.
    def save_all(directory)
      require "fileutils"
      FileUtils.mkdir_p(directory)
      items.filter_map do |item|
        item.document.save(directory) if item.document && item.document.document_base64
      end
    end

    # Builds a result from the API response, correlating inputs to outcomes.
    #
    # The API returns a flat +documents+ list and a flat +issues+ list. Every
    # rendered document reports its own +document_index+, so it is placed at
    # exactly the slot of the input that produced it. That index is the only
    # correlation: a document whose index is absent or out of range is dropped,
    # never guessed onto a slot by position. Issues attach to their slot the
    # same way (batch-wide issues, whose index is +nil+, attach to every item).
    # Any slot left empty and reasonless gets a synthesised "not rendered"
    # issue.
    def self.from_api(data, inputs: nil)
      status = data.fetch("status", "ok")
      rendered_count = data.fetch("renderedCount", 0)
      requested_count = data.fetch("requestedCount", 0)

      docs = (data["documents"] || []).map { |d| RenderedDocument.from_api(d) }
      all_issues = (data["issues"] || []).map { |i| RenderIssue.from_api(i) }

      count =
        if requested_count.is_a?(Integer) && requested_count.positive?
          requested_count
        elsif !inputs.nil?
          inputs.length
        else
          docs.length
        end

      items = Array.new(count) do |i|
        BatchItem.new(
          index: i,
          input: (inputs && i < inputs.length ? inputs[i] : nil),
          issues: []
        )
      end

      # Distribute issues; batch-wide issues (index nil) attach to every item.
      all_issues.each do |issue|
        index = issue.document_index
        if index.nil?
          items.each { |item| item.issues << issue }
        elsif index >= 0 && index < items.length
          items[index].issues << issue
        end
      end

      # Place each document at the slot it reports via document_index. That index
      # is the only correlation: a document whose index is absent or out of range
      # is dropped, never guessed onto a slot by position.
      docs.each do |doc|
        index = doc.document_index
        items[index].document = doc if index.is_a?(Integer) && index >= 0 && index < items.length
      end

      # Anything left without a document or a reason is a silent render failure.
      items.each do |item|
        next unless item.document.nil? && item.issues.empty?

        item.issues = [RenderIssue.new(
          type: RenderIssueType::UNKNOWN,
          severity: RenderIssueSeverity::ERROR,
          description: "not rendered",
          document_index: item.index
        )]
      end

      requested = requested_count.is_a?(Integer) && requested_count.positive? ? requested_count : count
      rendered = rendered_count.is_a?(Integer) && rendered_count.positive? ? rendered_count : docs.length

      new(
        items: items,
        status: status,
        message: data["message"],
        requested_count: requested,
        rendered_count: rendered,
        # +missing_count+ is by definition +requested_count - rendered_count+, so it is computed
        # here rather than read from the response. Clamped at 0 so a server sending
        # rendered > requested can never produce a negative count.
        missing_count: [requested - rendered, 0].max
      )
    end
  end

  # Reference to an enqueued async render job, returned by
  # Client#enqueue_batch_render. +state+ is normally :queued on creation;
  # track progress via webhook callbacks or by polling Client#job_status (or
  # Client#wait_for_job).
  class RenderJob
    attr_reader :job_id, :requested_count, :state

    def initialize(job_id:, requested_count: 0, state: RenderJobState::UNKNOWN)
      @job_id = job_id
      @requested_count = requested_count
      @state = state
    end

    def self.from_api(data)
      new(
        job_id: Common.require(data, "jobId"),
        requested_count: data.fetch("requestedCount", 0),
        state: RenderJobState.from_api(data["state"])
      )
    end

    def to_s
      "RenderJob #{job_id} — #{requested_count} doc(s), state=#{RenderJobState.to_wire(state)}"
    end
  end

  # Status of an async render job, returned by Client#job_status.
  #
  # +state+ and +status+ are separate: +state+ is the job lifecycle
  # (:queued/:pending are non-terminal; :completed/:failed/:unknown are
  # terminal); +status+ is the render outcome (:ok/:partial/:failed/
  # :insufficient_credit/:unknown) and is +nil+ while the job is still
  # pending. +missing_count+ is every document not rendered, whatever the
  # reason; +issues+ carries the per-document diagnostics.
  class RenderJobStatus
    attr_reader :job_id, :state, :status, :rendered_count, :requested_count,
                :missing_count, :started_at, :completed_at, :failure_reason,
                :issues

    def initialize(job_id:, state:, status: nil, rendered_count: 0,
                   requested_count: 0, missing_count: 0, started_at:,
                   completed_at: nil, failure_reason: nil, issues: [])
      @job_id = job_id
      @state = state
      @status = status
      @rendered_count = rendered_count
      @requested_count = requested_count
      @missing_count = missing_count
      @started_at = started_at
      @completed_at = completed_at
      @failure_reason = failure_reason
      @issues = issues
    end

    # True once the job reached a terminal state. :unknown counts as
    # terminal (fail-open) so an unrecognised server state ends a
    # Client#wait_for_job poll loop rather than spinning forever.
    def done?
      RenderJobState.terminal?(state)
    end

    # True when the job completed successfully.
    def ok?
      state == RenderJobState::COMPLETED && status == RenderOutcome::OK
    end

    # True when the job stopped early because the organisation ran out of
    # credit.
    def insufficient_credit?
      status == RenderOutcome::INSUFFICIENT_CREDIT
    end

    def self.from_api(data)
      new(
        job_id: Common.require(data, "jobId"),
        state: RenderJobState.from_api(data["state"]),
        status: data["status"].nil? ? nil : RenderOutcome.from_api(data["status"]),
        rendered_count: data.fetch("renderedCount", 0),
        requested_count: data.fetch("requestedCount", 0),
        missing_count: data.fetch("missingCount", 0),
        started_at: Common.parse_time!(Common.require(data, "startedAt")),
        completed_at: Common.parse_time(data["completedAt"]),
        failure_reason: data["failureReason"],
        issues: (data["issues"] || []).map { |i| RenderIssue.from_api(i) }
      )
    end

    def to_s
      "RenderJobStatus #{job_id} — state=#{RenderJobState.to_wire(state)} " \
        "status=#{status.nil? ? 'nil' : RenderOutcome.to_wire(status)} " \
        "(#{rendered_count} rendered)"
    end
  end
end
