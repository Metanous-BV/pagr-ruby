# frozen_string_literal: true

require_relative "common"

module Pagr
  # Metadata for a persisted rendered document, as returned by
  # Client#documents / Client#document.
  #
  # +document_base64+ carries the PDF bytes only when the document was rendered
  # with +include_document: true+; otherwise call Client#download_document to
  # fetch them. +is_pdf_deleted+ is true once the stored PDF has been purged by
  # retention — Client#download_document then fails with HTTP 410 while this
  # metadata stays available.
  class RenderDocument
    attr_reader :id, :document_name, :template_id, :version_number, :environment,
                :file_size_bytes, :page_count, :rendered_at, :render_duration,
                :view_url, :document_type, :is_pdf_deleted, :language,
                :document_base64

    def initialize(id:, document_name:, template_id:, version_number:,
                   environment:, file_size_bytes:, page_count:, rendered_at:,
                   render_duration:, view_url:, document_type:,
                   is_pdf_deleted: false, language: nil, document_base64: nil)
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
      @is_pdf_deleted = is_pdf_deleted
      @language = language
      @document_base64 = document_base64
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
        is_pdf_deleted: data.fetch("isPdfDeleted", false),
        language: data["language"],
        document_base64: data["documentBase64"]
      )
    end

    # True when the stored PDF has been purged by retention.
    def pdf_deleted?
      is_pdf_deleted
    end

    def to_s
      "RenderDocument #{document_name} (#{id})"
    end
  end

  # A page of results. Enumerable over +items+ (+each+, +[]+, +size+, plus
  # everything Enumerable provides).
  #
  # +total+ is the number of matching records across all pages, not just this
  # one. +skip+/+take+ echo the paging the server applied (+take+ defaults to 25
  # and is clamped to 1-200 server-side). There is no auto-pager: advance +skip+
  # by the page +size+ to walk pages while #more? is true.
  class PagedResult
    include Enumerable

    attr_reader :items, :total, :skip, :take

    def initialize(items: [], total: 0, skip: 0, take: 0)
      @items = items
      @total = total
      @skip = skip
      @take = take
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

    # True when more records exist beyond this page.
    def more?
      skip + items.length < total
    end

    # Builds a page from the API response. The block maps each raw item Hash to
    # a typed model (e.g. +PagedResult.from_api(body) { |h| Template.from_api(h) }+).
    def self.from_api(data, &item_factory)
      new(
        items: (data["items"] || []).map { |item| item_factory.call(item) },
        total: data.fetch("total", 0),
        skip: data.fetch("skip", 0),
        take: data.fetch("take", 0)
      )
    end
  end
end
