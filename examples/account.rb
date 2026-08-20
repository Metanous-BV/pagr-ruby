# frozen_string_literal: true

require_relative "_env"

# Inspect organisation usage/credit and available fonts.
client = Example.client

stats = client.org_stats
puts "Organisation: #{stats.organisation_name} (#{stats.tier})"
puts "Period: #{stats.period_start} -> #{stats.period_end}"

# Counts are +nil+ when the API omitted the field (not the same as a genuine 0);
# -1 in an "available" field means unlimited for the organisation's tier.
def quota(used, available)
  return "not reported" if used.nil? && available.nil?

  available == -1 ? "#{used} used / unlimited" : "#{used} used / #{available} remaining"
end

puts "Pages:  #{quota(stats.pages_used_this_period, stats.pages_available)}"
puts "Tokens: #{quota(stats.tokens_used_this_period, stats.tokens_available)}"

puts "Fonts:  #{client.fonts.join(', ')}"
