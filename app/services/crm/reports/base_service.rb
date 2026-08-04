# Common scoping shared by every CRM funnel metric.
#
# `deals_scope` is meant to receive `policy_scope(Crm::Deal)`: the `restrito_por_owner` visibility
# rule has to hold for aggregates too, otherwise an agent restricted to their own cards could still
# read the whole pipeline value out of the totals.
#
# Every metric filters on the timestamp that reads naturally for it, and the choice is part of the
# contract of each endpoint:
#   - pipeline movement (funnel, time per stage) -> `crm_deals.created_at`
#   - closed business (sales cycle, sources, loss reasons) -> `crm_deals.closed_at`
#   - forecast -> `crm_deals.expected_close_on`
class Crm::Reports::BaseService
  def initialize(account:, deals_scope: Crm::Deal, pipeline_id: nil, range: nil)
    @account = account
    @deals_scope = deals_scope
    @pipeline_id = pipeline_id.presence
    @range = range
  end

  private

  attr_reader :account, :pipeline_id, :range

  # Archived deals are out of every metric. The account filter is reapplied on top of the policy
  # scope on purpose: a metric must never be able to cross accounts, even if a caller hands over a
  # scope that forgot it.
  def base_deals
    scope = @deals_scope.active.where(account_id: @account.id)
    scope = scope.where(pipeline_id: @pipeline_id) if @pipeline_id
    scope
  end

  def deals_between(column)
    return base_deals if @range.blank?

    base_deals.where(crm_deals: { column => @range })
  end

  # Stages are listed even when no deal ever touched them, so the funnel keeps the shape of the
  # pipeline instead of only showing the columns that happen to have data.
  def stages
    scope = Crm::Stage.where(account_id: @account.id)
    scope = scope.where(pipeline_id: @pipeline_id) if @pipeline_id
    scope.order(:pipeline_id, :position, :id)
  end
end
