# frozen_string_literal: true

require "time"
require_relative "../errors"

module Pagr
  # Internal helpers shared by the model +from_api+ factories. Not part of the
  # public API.
  module Common
    module_function

    # Parses an ISO-8601 timestamp from the API into a UTC +Time+, or +nil+ for
    # missing/blank values. Timestamps carrying no zone offset are interpreted
    # as UTC, matching the API contract that all timestamps are UTC.
    def parse_time(value)
      return nil if value.nil?

      str = value.to_s
      return nil if str.strip.empty?

      if str.match?(/(?:[zZ]|[+-]\d{2}:?\d{2})\z/)
        Time.parse(str).utc
      else
        # No zone offset: interpret the wall-clock time as UTC.
        Time.parse("#{str}Z").utc
      end
    end

    # Like #parse_time, but raises PagrDecodeError instead of returning nil
    # for a missing/blank value. Use for fields the API always sends.
    def parse_time!(value)
      parsed = parse_time(value)
      return parsed unless parsed.nil?

      raise PagrDecodeError, "the Pagr API response is missing a required timestamp"
    end

    # Returns data[key], raising PagrDecodeError if the key is absent. Use for
    # fields a from_api factory cannot sensibly default.
    def require(data, key)
      raise PagrDecodeError, "the Pagr API response is missing required field #{key.inspect}" unless data.key?(key)

      data[key]
    end

    # Reduces a server-supplied document name to a bare, safe filename.
    #
    # +document_name+ is data (it can embed values bound from the render
    # payload, via the document-name-template feature), not a path, so it
    # must never be able to steer a #save outside the target directory. This
    # strips any directory components, drive letters and traversal so the
    # result is always a single path segment.
    def safe_filename(name)
      # -1 keeps a trailing separator's empty segment (unlike the default
      # split, which drops trailing empty strings) so "foo/" reduces to ""
      # rather than "foo".
      stripped = name.to_s.tr("\\", "/").split("/", -1).last.to_s
      stripped = stripped.sub(/\A[A-Za-z]:/, "") # drop a Windows drive letter (e.g. "C:")
      stripped = stripped.sub(%r{\A[/\\]+}, "").strip
      ["", ".", ".."].include?(stripped) ? "document" : stripped
    end
  end
end
