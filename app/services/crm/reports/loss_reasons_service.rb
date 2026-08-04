# Why deals are lost: count and value per `crm_lost_reasons`.
#
# Lost deals with no reason recorded come back under a `nil` reason — they are exactly the ones a
# manager wants to see, since they mean the team is closing cards without saying why.
class Crm::Reports::LossReasonsService < Crm::Reports::BaseService
  def perform
    rows = totals_by_lost_reason_id
    return [] if rows.empty?

    reasons_by_id = Crm::LostReason.where(account_id: account.id, id: rows.map(&:first).compact).index_by(&:id)

    rows.map do |lost_reason_id, deals_count, value_cents|
      {
        lost_reason: reasons_by_id[lost_reason_id],
        deals_count: deals_count.to_i,
        value_cents: value_cents.to_i
      }
    end
  end

  private

  def totals_by_lost_reason_id
    deals_between(:closed_at)
      .lost
      .group(:lost_reason_id)
      .order(Arel.sql('COUNT(*) DESC'))
      .pluck(:lost_reason_id, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(crm_deals.value_cents), 0)'))
  end
end
