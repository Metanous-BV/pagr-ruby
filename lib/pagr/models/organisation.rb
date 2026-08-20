# frozen_string_literal: true

require_relative "common"

module Pagr
  # Usage and credit statistics for the authenticated organisation, covering the
  # current billing period (+period_start+..+period_end+).
  #
  # "Pages" is the render-credit unit (rendered document pages); "tokens" are AI
  # tokens consumed by AI-assisted template features. A value of +-1+ in
  # +pages_available+, +included_tokens_per_month+ or +tokens_available+ means
  # unlimited for the organisation's +tier+.
  #
  # Every usage/count field defaults to +nil+ (field absent) rather than +0+, so
  # a server that omits a field is distinguishable from a genuine zero — check
  # for +nil+ before doing arithmetic on them.
  class OrgStats
    attr_reader :organisation_name, :period_start, :period_end, :tier,
                :included_renders_per_month, :pages_used_this_period,
                :pages_available, :included_tokens_per_month,
                :tokens_used_this_period, :tokens_available, :user_count

    def initialize(organisation_name:, period_start:, period_end:, tier:,
                   included_renders_per_month:, pages_used_this_period:,
                   pages_available:, included_tokens_per_month:,
                   tokens_used_this_period:, tokens_available:, user_count:)
      @organisation_name = organisation_name
      @period_start = period_start
      @period_end = period_end
      @tier = tier
      @included_renders_per_month = included_renders_per_month
      @pages_used_this_period = pages_used_this_period
      @pages_available = pages_available
      @included_tokens_per_month = included_tokens_per_month
      @tokens_used_this_period = tokens_used_this_period
      @tokens_available = tokens_available
      @user_count = user_count
    end

    def self.from_api(data)
      new(
        organisation_name: data["organisationName"],
        period_start: Common.parse_time(data["periodStart"]),
        period_end: Common.parse_time(data["periodEnd"]),
        tier: data["tier"],
        included_renders_per_month: data["includedRendersPerMonth"],
        pages_used_this_period: data["pagesUsedThisPeriod"],
        pages_available: data["pagesAvailable"],
        included_tokens_per_month: data["includedTokensPerMonth"],
        tokens_used_this_period: data["tokensUsedThisPeriod"],
        tokens_available: data["tokensAvailable"],
        user_count: data["userCount"]
      )
    end

    def to_s
      "OrgStats | #{organisation_name || '?'} (#{tier})"
    end
  end
end
