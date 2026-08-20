# frozen_string_literal: true

require "json"
require_relative "common"

module Pagr
  # A document template as listed by the API.
  #
  # Carries the template's identity and catalogue metadata (project, latest
  # version number, audit fields). The template content itself lives on its
  # versions — fetch one with Client#template_version.
  #
  # +latest_version_number+ is the newest *published* version (+nil+ if none has
  # been published yet); +version_count+ is the total number of versions,
  # published or not. +master_template_id+/+master_template_name+ identify the
  # master template this one is a child of, when it has one.
  class Template
    attr_reader :id, :name, :document_name_template, :project_id, :project_name,
                :latest_version_number, :version_count, :updated_at, :updated_by,
                :master_template_id, :master_template_name

    def initialize(id:, name:, document_name_template: nil, project_id: nil,
                   project_name: nil, latest_version_number: nil, version_count: 0,
                   updated_at: nil, updated_by: nil, master_template_id: nil,
                   master_template_name: nil)
      @id = id
      @name = name
      @document_name_template = document_name_template
      @project_id = project_id
      @project_name = project_name
      @latest_version_number = latest_version_number
      @version_count = version_count
      @updated_at = updated_at
      @updated_by = updated_by
      @master_template_id = master_template_id
      @master_template_name = master_template_name
    end

    def self.from_api(data)
      new(
        id: data["id"],
        name: data["name"],
        document_name_template: data["documentNameTemplate"],
        project_id: data["projectId"],
        project_name: data["projectName"],
        latest_version_number: data["latestVersionNumber"],
        version_count: data.fetch("versionCount", 0),
        updated_at: Common.parse_time(data["updatedAt"]),
        updated_by: data["updatedBy"],
        master_template_id: data["masterTemplateId"],
        master_template_name: data["masterTemplateName"]
      )
    end

    def to_s
      "#{name} (#{id})"
    end
  end

  # A single version of a template.
  #
  # +template_json+ is the template DSL as a raw JSON string (there is no typed
  # model for it). +sample_data+ has already been parsed to a Hash — it matches
  # the version's bindings and is a good starting point for building your own
  # document data; parsing is lenient, so absent, malformed, or non-object
  # sample data all yield +{}+. +translations+ is a raw JSON string, or +nil+
  # when the version has no translations.
  class TemplateVersion
    attr_reader :id, :version_number, :template_json, :sample_data,
                :document_name_template, :published_at, :published_by,
                :template_id, :updated_at, :translations

    def initialize(id:, version_number:, template_json:, sample_data:,
                   document_name_template:, published_at:, published_by:,
                   template_id:, updated_at:, translations: nil)
      @id = id
      @version_number = version_number
      @template_json = template_json
      @sample_data = sample_data
      @document_name_template = document_name_template
      @published_at = published_at
      @published_by = published_by
      @template_id = template_id
      @updated_at = updated_at
      @translations = translations
    end

    def self.from_api(data)
      new(
        id: data["id"],
        version_number: data["versionNumber"],
        template_json: data["templateJson"],
        sample_data: parse_sample_data(data["sampleData"]),
        document_name_template: data["documentNameTemplate"],
        published_at: Common.parse_time(data["publishedAt"]),
        published_by: data["publishedBy"],
        template_id: data["templateId"],
        updated_at: Common.parse_time(data["updatedAt"]),
        translations: data["translations"]
      )
    end

    # The API sends sample data as a JSON string; parse it to a Hash. Parsing is
    # deliberately lenient — absent, blank, malformed, or non-object JSON all
    # yield an empty Hash. Sample data is authored content on the template, so a
    # broken one must not take down an otherwise fine Client#template_version;
    # letting JSON::ParserError escape would also break the SDK's promise that
    # callers only ever catch Pagr::Error.
    def self.parse_sample_data(raw)
      case raw
      when Hash then raw
      when String
        return {} if raw.strip.empty?

        parsed = begin
          JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end
        parsed.is_a?(Hash) ? parsed : {}
      else {}
      end
    end

    def to_s
      "v#{version_number} — #{document_name_template}"
    end
  end
end
