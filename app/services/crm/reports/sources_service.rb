# Wins and losses broken down by the source (channel) the deal came from — the metric that answers
# "which channel brings money", which is the whole point of tying a source to the card.
#
# Deals with no source are reported under a `nil` source instead of being dropped: a channel that
# stops being tagged has to show up as a hole, not disappear from the total.
class Crm::Reports::SourcesService < Crm::Reports::BaseService
  STATUSES = %w[won lost].freeze
  EMPTY = { won_count: 0, won_value_cents: 0, lost_count: 0, lost_value_cents: 0 }.freeze

  def perform
    totals = totals_by_source_and_status
    return [] if totals.empty?

    sources_by_id = Crm::Source.where(account_id: account.id, id: totals.keys.compact).index_by(&:id)

    totals.map { |source_id, row| build_row(sources_by_id[source_id], row) }
          .sort_by { |row| -row[:won_value_cents] }
  end

  private

  # A single grouped query over (source, status); the split into won/lost columns is just a
  # reshape of the rows Postgres already aggregated.
  def totals_by_source_and_status
    rows = deals_between(:closed_at)
           .where(status: STATUSES)
           .group(:source_id, :status)
           .pluck(:source_id, :status, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(crm_deals.value_cents), 0)'))

    rows.each_with_object({}) do |(source_id, status, count, value_cents), acc|
      status_name = Crm::Deal.statuses.key(status) || status.to_s
      entry = acc[source_id] ||= EMPTY.dup
      entry[:"#{status_name}_count"] = count.to_i
      entry[:"#{status_name}_value_cents"] = value_cents.to_i
    end
  end

  def build_row(source, totals)
    closed_count = totals[:won_count] + totals[:lost_count]

    {
      source: source,
      won_count: totals[:won_count],
      won_value_cents: totals[:won_value_cents],
      lost_count: totals[:lost_count],
      lost_value_cents: totals[:lost_value_cents],
      win_rate: closed_count.zero? ? 0.0 : (totals[:won_count] * 100.0 / closed_count).round(2)
    }
  end
end
