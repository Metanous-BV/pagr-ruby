# frozen_string_literal: true

require_relative "_env"

# Show the difference between transport errors (exceptions) and business
# outcomes (data on the result).
client = Example.client

# 1) A bad template ID raises a typed exception.
begin
  client.template("00000000-0000-0000-0000-000000000000")
rescue Pagr::NotFoundError => e
  puts "Not found (#{e.status_code}, code=#{e.code}): #{e.message}"
rescue Pagr::Error => e
  puts "Pagr error (#{e.status_code}): #{e.message}"
end

# 2) A render that fails validation is NOT an exception — inspect the result.
result = client.render(Example.template_id, { "deliberately" => "incomplete" })
if result.ok?
  puts "Rendered despite sparse data."
else
  puts "Render blocked (#{result.status}):"
  result.issues.each { |issue| puts "  #{issue.error? ? 'ERROR' : 'warn '} #{issue.type}: #{issue.description}" }
end
