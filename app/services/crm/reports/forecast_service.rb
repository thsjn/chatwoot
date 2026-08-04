# Weighted forecast of the open pipeline, bucketed by the month of `expected_close_on`.
#
# The weight is the `probability` of the stage the deal is in, so the numbers move as cards
# progress without anyone typing a percentage per deal. The raw (unweighted) sum ships alongside
# because both readings are used: the weighted one to commit a number, the raw one to see the
# ceiling of the month.
#
# Only OPEN deals are in the forecast: a won deal is revenue, not a forecast, and a lost one is
# nothing.
class Crm::Reports::ForecastService < Crm::Reports::BaseService
  PERIOD_SQL = "date_trunc('month', crm_deals.expected_close_on)".freeze

  def perform
    rows_by_period.map do |period, value_cents, weighted_value_cents, deals_count|
      {
        period: period&.to_date,
        deals_count: deals_count.to_i,
        value_cents: value_cents.to_i,
        weighted_value_cents: weighted_value_cents.to_f.round
      }
    end
  end

  private

  # `probability` lives on the stage, so the join is what makes the weighting possible in SQL.
  # Deals without an expected close date land in a `null` bucket instead of being dropped: they are
  # real money with no date yet and the board has to see them.
  def rows_by_period
    deals_between(:expected_close_on)
      .open
      .joins(:stage)
      .group(Arel.sql(PERIOD_SQL))
      .order(Arel.sql("#{PERIOD_SQL} ASC NULLS LAST"))
      .pluck(
        Arel.sql(PERIOD_SQL),
        Arel.sql('COALESCE(SUM(crm_deals.value_cents), 0)'),
        Arel.sql('COALESCE(SUM(crm_deals.value_cents * crm_stages.probability / 100.0), 0)'),
        Arel.sql('COUNT(*)')
      )
  end
end
