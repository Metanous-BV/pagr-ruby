# frozen_string_literal: true

require_relative "_env"

# Browse persisted documents and download one.
client = Example.client

page = client.documents(
  take: 10,
  sort_by: "renderedAt",
  sort_direction: "desc",
  filters: [{ field: "environment", value: "test" }]
)

puts "#{page.total} document(s):"
page.each { |doc| puts "  #{doc.document_name} — #{doc.page_count}p, #{doc.rendered_at}" }

first = page.items.first
if first
  if first.pdf_deleted?
    puts "#{first.document_name}: PDF purged by retention."
  else
    bytes = client.download_document(first.id)
    File.binwrite("downloaded.pdf", bytes)
    puts "Downloaded #{bytes.bytesize} bytes to downloaded.pdf"
  end
end
