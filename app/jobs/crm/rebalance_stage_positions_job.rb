# Other half of the fractional indexing `Crm::Deal` documents: dropping a card between two
# neighbours writes the average of their positions, which keeps a move to a single UPDATE but
# halves the room left in that interval every time. This job renumbers a whole column back to even
# multiples of `Crm::Deal::POSITION_GAP`, restoring the slack without moving a single card.
#
# It is enqueued by `Crm::MoveDealService` when the gap between two neighbours falls under
# `Crm::Deal::POSITION_REBALANCE_THRESHOLD`, so the rewrite never runs inside the request that
# dragged the card.
class Crm::RebalanceStagePositionsJob < ApplicationJob
  include Events::Types

  queue_as :low

  def perform(stage_id)
    stage = Crm::Stage.find_by(id: stage_id)
    return if stage.blank?
    return if rewrite_positions(stage).zero?

    Rails.configuration.dispatcher.dispatch(CRM_STAGE_POSITIONS_REBALANCED, Time.zone.now, stage: stage)
  end

  private

  # `lock_version` is deliberately NOT bumped, and neither is `updated_at`.
  #
  # `lock_version` answers one question — "did somebody else move THIS card while I was holding
  # it?" — and the whole point of the rebalance is that the answer here is no: the order on screen
  # is byte for byte the one the user is looking at, only the numbers behind it changed. Bumping it
  # would make every card of the column stale at once, and the next drag on any board that had the
  # column open would come back as a 409 telling the user to reload over a housekeeping rewrite
  # they never caused. So the statement writes `position` and nothing else, which leaves the
  # optimistic lock free to keep guarding real concurrent edits.
  #
  # The clients are not left with stale numbers either: the job broadcasts
  # `crm_stage.positions_rebalanced` and the board refetches that column, which is what keeps a
  # later drop from computing a midpoint out of positions that no longer exist.
  #
  # `FOR UPDATE` holds the rows for the duration of the rewrite so a concurrent move cannot slot a
  # card between two positions that are about to be renumbered. Archived cards are skipped: they
  # are off the board, and their positions are never split against.
  def rewrite_positions(stage)
    Crm::Deal.transaction do
      ids = Crm::Deal.where(stage_id: stage.id).active.ordered.lock('FOR UPDATE').pluck(:id)
      next 0 if ids.empty?

      Crm::Deal.connection.update(update_positions_sql(ids))
      ids.size
    end
  end

  # One statement for the whole column: a per-row UPDATE would be as many round trips as there are
  # cards, all of them holding the row locks taken above.
  def update_positions_sql(ids)
    values = ids.each_with_index.map { |id, index| "(#{id.to_i}, #{(index + 1) * Crm::Deal::POSITION_GAP})" }.join(', ')

    <<~SQL.squish
      UPDATE crm_deals AS d
         SET position = v.position
        FROM (VALUES #{values}) AS v(id, position)
       WHERE d.id = v.id
    SQL
  end
end
