# Average time a deal spends in each stage, in seconds (the UI formats it).
#
# `duration_seconds` on a transition is the time spent in the stage the deal was LEAVING, so the
# average is grouped by `from_stage_id` and not by `to_stage_id`. The value is recorded once, when
# the card moves, so nothing is recomputed from the current state of the deal here.
#
# Only completed stays are averaged: a deal still sitting in a stage has not produced a transition
# out of it yet and does not pull the average down.
class Crm::Reports::StageDurationsService < Crm::Reports::BaseService
  def perform
    durations = durations_by_stage_id

    stages.map do |stage|
      row = durations[stage.id]

      {
        stage: stage,
        avg_duration_seconds: row ? row.first.to_f.round : nil,
        transitions_count: row ? row.last.to_i : 0
      }
    end
  end

  private

  # AVG skips NULL `duration_seconds`, and COUNT(duration_seconds) counts the same rows the average
  # was built from, so the sample size published next to it is honest.
  def durations_by_stage_id
    Crm::StageTransition
      .joins("INNER JOIN (#{deals_between(:created_at).select(:id).to_sql}) scoped_deals ON scoped_deals.id = crm_stage_transitions.deal_id")
      .where.not(from_stage_id: nil)
      .group(:from_stage_id)
      .pluck(:from_stage_id, Arel.sql('AVG(crm_stage_transitions.duration_seconds)'), Arel.sql('COUNT(crm_stage_transitions.duration_seconds)'))
      .to_h { |stage_id, average, count| [stage_id, [average, count]] }
  end
end
