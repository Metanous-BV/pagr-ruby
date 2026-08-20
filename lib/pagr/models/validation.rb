# frozen_string_literal: true

require_relative "render"

module Pagr
  # Validation results for a batch of documents. The API returns a single flat
  # list of RenderIssues; each issue carries the +document_index+ it pertains to
  # (+nil+ for batch-wide issues).
  #
  # #valid? is the production gate: it is +true+ only when no issue is
  # blocking production (i.e. +:warning+ or +:error+ severity). Callers who
  # want the narrower, Error-only check should inspect #errors directly
  # instead. Enumerable over the issues.
  class ValidationResponse
    include Enumerable

    attr_reader :issues

    def initialize(issues: [])
      @issues = issues
    end

    def each(&block)
      issues.each(&block)
    end

    def [](index)
      issues[index]
    end

    def size
      issues.size
    end
    alias length size

    # True when no issue is +:warning+ or +:error+ severity (i.e. no issue
    # blocks a production render). For the narrower, Error-only check, use
    # #errors directly.
    def valid?
      issues.none?(&:blocking_production?)
    end

    # The +:error+-severity issues.
    def errors
      issues.select(&:error?)
    end

    # The +:warning+-severity issues.
    def warnings
      issues.select { |i| i.severity == RenderIssueSeverity::WARNING }
    end

    # Issues pertaining to a specific document, including batch-wide issues
    # (those whose +document_index+ is +nil+).
    def issues_for(document_index)
      issues.select { |i| i.document_index.nil? || i.document_index == document_index }
    end

    def self.from_api(data)
      new(issues: (data["issues"] || []).map { |i| RenderIssue.from_api(i) })
    end

    def to_s
      header = valid? ? "valid" : "#{errors.length} error(s), #{warnings.length} warning(s)"
      body = issues.map { |i| "  #{i}" }.join("\n")
      body.empty? ? "ValidationResponse (#{header})" : "ValidationResponse (#{header})\n#{body}"
    end
  end
end
