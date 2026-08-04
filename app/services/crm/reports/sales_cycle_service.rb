# Sales cycle: average time between the creation of the deal and its closing, split by outcome.
#
# Won and lost are reported separately because they answer different questions: how long it takes
# to earn a customer, and how long the team burns on business it will not win.
class Crm::Reports::SalesCycleService < Crm::Reports::BaseService
  STATUSES = %w[won lost].freeze

  def perform
    rows = cycle_by_status

    STATUSES.index_with do |status|
      row = rows[status]

      {
        avg_cycle_seconds: row ? row.first.to_f.round : nil,
        deals_count: row ? row.last.to_i : 0
      }
    end
  end

  private

  # The subtraction of two timestamps yields an interval; EXTRACT(EPOCH ...) turns it into seconds
  # so Postgres does the averaging.
  def cycle_by_status
    deals_between(:closed_at)
      .where(status: STATUSES)
      .where.not(closed_at: nil)
      .group(:status)
      .pluck(:status, Arel.sql('AVG(EXTRACT(EPOCH FROM (crm_deals.closed_at - crm_deals.created_at)))'), Arel.sql('COUNT(*)'))
      .to_h { |status, average, count| [Crm::Deal.statuses.key(status) || status.to_s, [average, count]] }
  end
end
