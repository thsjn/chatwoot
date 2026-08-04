# Conversion funnel: how many deals reached each stage and how many of them moved past it.
#
# `crm_stage_transitions` is the source of truth, never the current `stage_id` of the deal: a card
# that already went through Qualification and now sits in Proposal has to count for both.
#
# A deal "visited" a stage when a transition points AT it (`to_stage_id`), and that is the whole
# rule: creating a deal writes a transition into its initial stage (`from_stage_id` NULL), so the
# entry into the funnel is recorded like any other move and the top of the funnel counts every
# card that ever entered it. The set is DISTINCT, so a card that bounced back into the same stage
# twice is still counted once.
#
# "Advanced" means the deal reached, at any point, a stage positioned after this one in the
# pipeline; the conversion rate is that count over the deals that entered.
class Crm::Reports::FunnelService < Crm::Reports::BaseService
  def perform
    counts = counts_by_stage_id

    stages.map do |stage|
      row = counts[stage.id] || {}
      entered = row['entered_count'].to_i
      advanced = row['advanced_count'].to_i

      {
        stage: stage,
        entered_count: entered,
        advanced_count: advanced,
        conversion_rate: entered.zero? ? 0.0 : (advanced * 100.0 / entered).round(2)
      }
    end
  end

  private

  def counts_by_stage_id
    ActiveRecord::Base.connection.select_all(funnel_sql).index_by { |row| row['stage_id'] }
  end

  # One statement, all the aggregation in Postgres: the deals never reach Ruby.
  # `scoped_deals` inlines the policy scoped relation, so account isolation, the archived filter,
  # the pipeline filter and the date range all ride along.
  def funnel_sql
    <<~SQL.squish
      WITH scoped_deals AS (#{deals_between(:created_at).select(:id).to_sql}),
      visits AS (
        SELECT DISTINCT t.deal_id, t.to_stage_id AS stage_id
          FROM crm_stage_transitions t
          JOIN scoped_deals d ON d.id = t.deal_id
      ),
      positioned AS (
        SELECT v.deal_id, v.stage_id, s.position
          FROM visits v
          JOIN crm_stages s ON s.id = v.stage_id
      ),
      reached AS (
        SELECT deal_id, MAX(position) AS max_position FROM positioned GROUP BY deal_id
      )
      SELECT p.stage_id,
             COUNT(*) AS entered_count,
             COUNT(*) FILTER (WHERE r.max_position > p.position) AS advanced_count
        FROM positioned p
        JOIN reached r ON r.deal_id = p.deal_id
       GROUP BY p.stage_id
    SQL
  end
end
