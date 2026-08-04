# Deals used to be created without any stage transition, which left the funnel report guessing
# where each card entered the pipeline. Creation now records a transition with `from_stage_id`
# NULL, and the report reads only those rows, so every deal already in the database needs its
# missing entry or it would vanish from the top of the funnel.
#
# The stage the deal was created in is the origin stage of its earliest transition, and the
# current stage for a card that never moved. `automated` is derived from the origin conversation
# link: a card with one came from the conversation ingestion, everything else was a human action.
class BackfillCrmDealCreationTransitions < ActiveRecord::Migration[7.1]
  def up
    execute(<<~SQL.squish)
      INSERT INTO crm_stage_transitions (deal_id, from_stage_id, to_stage_id, user_id, duration_seconds, automated, created_at)
      SELECT d.id,
             NULL,
             COALESCE(first_move.from_stage_id, d.stage_id),
             NULL,
             NULL,
             EXISTS (SELECT 1 FROM crm_deal_conversations dc WHERE dc.deal_id = d.id AND dc.is_origin IS TRUE),
             d.created_at
        FROM crm_deals d
        LEFT JOIN LATERAL (
          SELECT t.from_stage_id
            FROM crm_stage_transitions t
           WHERE t.deal_id = d.id
             AND t.from_stage_id IS NOT NULL
           ORDER BY t.created_at, t.id
           LIMIT 1
        ) first_move ON TRUE
       WHERE NOT EXISTS (
         SELECT 1 FROM crm_stage_transitions t WHERE t.deal_id = d.id AND t.from_stage_id IS NULL
       )
    SQL
  end

  def down
    execute('DELETE FROM crm_stage_transitions WHERE from_stage_id IS NULL')
  end
end
