# Totals of a pipeline broken down by stage, counting only the deals that are still in play
# (not archived and still open). The board header shows the totals of the WHOLE stage, not of
# the page currently loaded, and the forecast reads the same numbers, so the calculation lives
# here and always resolves as a single grouped query for every stage of the pipeline.
#
# `deals_scope` defaults to every deal of the pipeline; callers serving a request should pass
# `policy_scope(Crm::Deal)` so the totals respect the `restrito_por_owner` visibility rule.
class Crm::StageAggregatesService
  EMPTY = { deals_count: 0, deals_value_cents: 0 }.freeze

  def initialize(pipeline:, deals_scope: Crm::Deal)
    @pipeline = pipeline
    @deals_scope = deals_scope
  end

  # Returns a hash keyed by stage id defaulting to `EMPTY`, so a stage with no deals still
  # renders zeros without a second query.
  def perform
    Hash.new(EMPTY).merge(totals_by_stage_id)
  end

  private

  # `SUM` over a bigint returns numeric in Postgres, which Rails maps to BigDecimal and jbuilder
  # serialises as a STRING ("100000.0"). The board does arithmetic with these totals on every
  # optimistic move, so they have to reach the client as integers.
  def totals_by_stage_id
    @deals_scope.where(pipeline_id: @pipeline.id).active.where(status: :open)
                .group(:stage_id)
                .pluck(:stage_id, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(crm_deals.value_cents), 0)'))
                .to_h { |stage_id, count, value_cents| [stage_id, { deals_count: count.to_i, deals_value_cents: value_cents.to_i }] }
  end
end
