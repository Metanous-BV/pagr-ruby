# frozen_string_literal: true

require_relative "_env"

# Browse templates and versions, with sorting and filtering.
client = Example.client

page = client.templates(
  take: 10,
  sort_by: "name",
  filters: [{ field: "name", op: :contains, value: "invoice" }]
)
page.each { |template| puts "#{template.name}: #{template.version_count} version(s)" }

template_id = Example.template_id
versions = client.template_versions(template_id, sort_by: "versionNumber", sort_direction: "desc")
versions.each { |version| puts "  v#{version.version_number} published #{version.published_at}" }

latest = client.template_version(template_id)
puts "Latest published: v#{latest.version_number}"
puts "Sample data keys: #{latest.sample_data.keys.join(', ')}"
