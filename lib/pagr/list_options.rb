# frozen_string_literal: true

module Pagr
  # Comparison operators for a Filter. Serialised to the wire as the lowercase
  # string form (the default is +:eq+).
  module FilterOp
    EQ = :eq
    NEQ = :neq
    GT = :gt
    GTE = :gte
    LT = :lt
    LTE = :lte
    CONTAINS = :contains

    ALL = [EQ, NEQ, GT, GTE, LT, LTE, CONTAINS].freeze
  end

  # A single field filter for a list endpoint, serialised to the API's indexed
  # model-binding query form
  # (+filters[0].field=...&filters[0].op=...&filters[0].value=...+).
  #
  # Construct one directly, or pass a plain Hash
  # (+{ field: "name", op: :contains, value: "invoice" }+) anywhere a filter is
  # accepted — it is coerced for you.
  class Filter
    attr_reader :field, :op, :value

    def initialize(field:, value:, op: FilterOp::EQ)
      @field = field
      @op = op || FilterOp::EQ
      @value = value
    end

    # Normalises a Filter or a Hash (symbol- or string-keyed) into a Filter.
    def self.coerce(filter)
      return filter if filter.is_a?(Filter)

      Filter.new(
        field: filter[:field] || filter["field"],
        op: filter[:op] || filter["op"] || FilterOp::EQ,
        value: filter[:value] || filter["value"]
      )
    end
  end

  # Canonical per-endpoint filter field/operator tables, transcribed from the
  # reference implementation's +Python/pagr/filters.py+ (the authoritative
  # source).
  #
  # The server *silently ignores* an unknown filter field or operator and
  # returns the *unfiltered* result set — so a typo ("documentNam" for
  # "documentName") would not error, it would quietly return everything.
  # Pagr.build_list_query validates against these tables so that turns into an
  # immediate ArgumentError instead of a silently wrong result set. Field names
  # are the API's camelCase wire names.
  module Filters
    # Operator sets, reused across fields of the same kind.
    EQ = [FilterOp::EQ].freeze                                                        # ids/guids
    STRING = [FilterOp::EQ, FilterOp::CONTAINS].freeze                                # text fields
    ORD = [FilterOp::EQ, FilterOp::GT, FilterOp::GTE, FilterOp::LT, FilterOp::LTE].freeze
    ENUM = [FilterOp::EQ, FilterOp::NEQ].freeze                                       # closed vocab

    # Filters accepted by Client#templates (org-wide and project-scoped alike).
    TEMPLATES = {
      "name" => STRING,
      "project.guid" => EQ,
      "createdAt" => ORD,
      "updatedAt" => ORD
    }.freeze

    # Filters accepted by Client#template_versions.
    TEMPLATE_VERSIONS = {
      "versionNumber" => ORD,
      "publishedAt" => ORD,
      "createdAt" => ORD,
      "updatedAt" => ORD
    }.freeze

    # Filters accepted by Client#documents. Note +renderDuration+ can be sorted
    # on but not filtered, and +documentType+ supports neither — so neither
    # appears here.
    DOCUMENTS = {
      "documentName" => STRING,
      "template.guid" => EQ,
      "versionNumber" => ORD,
      "fileSizeBytes" => ORD,
      "pageCount" => ORD,
      "renderedAt" => ORD,
      "createdAt" => ORD,
      "updatedAt" => ORD,
      "environment" => ENUM,
      "language" => ENUM
    }.freeze
  end

  # Builds the query parameters for a list endpoint (templates, versions,
  # documents): +skip+, +take+, +sortBy+, +sortDirection+, +search+, then the
  # indexed +filters[i].field/.op/.value+ triples (op defaults to "eq"). Only
  # the options that are set appear in the result.
  #
  # +allowed+ is the calling endpoint's field/operator table (see Filters);
  # this builder is endpoint-agnostic and reusable, so each list method passes
  # its own table rather than validating against a single global vocabulary.
  # Raises ArgumentError for a field the endpoint does not accept, or an
  # operator that is not valid for that field — the server would otherwise
  # ignore the filter and return the unfiltered result set.
  def self.build_list_query(allowed, skip: nil, take: nil, sort_by: nil,
                            sort_direction: nil, filters: nil, search: nil)
    query = {}
    query["skip"] = skip unless skip.nil?
    query["take"] = take unless take.nil?
    query["sortBy"] = sort_by unless sort_by.nil?
    query["sortDirection"] = sort_direction unless sort_direction.nil?
    query["search"] = search unless search.nil?

    Array(filters).each_with_index do |raw, i|
      filter = Filter.coerce(raw)
      op = (filter.op || FilterOp::EQ).to_sym
      allowed_ops = allowed[filter.field.to_s]
      unless allowed_ops
        raise ArgumentError,
              "filters[#{i}]: unknown field #{filter.field.inspect} for this endpoint; " \
              "allowed fields: #{allowed.keys.sort.join(', ')}"
      end
      unless allowed_ops.include?(op)
        raise ArgumentError,
              "filters[#{i}]: operator #{op.inspect} is not valid for field " \
              "#{filter.field.inspect}; allowed operators: #{allowed_ops.join(', ')}"
      end

      query["filters[#{i}].field"] = filter.field
      query["filters[#{i}].op"] = op.to_s
      query["filters[#{i}].value"] = filter.value
    end

    query
  end
end
