# Indexes for the queries the CRM actually runs, all of them partial on `archived_at IS NULL`:
# every board and report query starts from `Crm::Deal.active`, so an archived card is dead weight
# in the index and the partial form keeps them out of it entirely.
class AddCrmPerformanceIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  INDEXES = [
    # Board column: `WHERE stage_id = ? AND archived_at IS NULL ORDER BY position, id LIMIT 25`,
    # plus the `count` behind the "load more" of that column. Trailing `id` matches the `ordered`
    # scope so the page is read straight off the index instead of sorting the whole column.
    # `index_crm_deals_on_stage_id_and_position` is kept: it is the one that still serves the
    # archived listing, which this partial index excludes by definition.
    [:crm_deals, %i[stage_id position id], 'index_crm_deals_active_on_stage_position'],
    # Column headers (`Crm::StageAggregatesService`): one grouped pass over the open, non archived
    # deals of a pipeline. Runs twice per board load (total + filtered), on every filter change.
    [:crm_deals, %i[pipeline_id status stage_id], 'index_crm_deals_active_on_pipeline_status_stage'],
    # Closed business reports (sales cycle, sources, loss reasons) filter a date range over
    # `closed_at` inside one account/pipeline.
    [:crm_deals, %i[account_id pipeline_id closed_at], 'index_crm_deals_active_on_account_pipeline_closed'],
    # Pipeline movement reports (funnel, stage durations) and the CSV export range over
    # `created_at` instead; the funnel also feeds this set into the transitions join as a CTE.
    [:crm_deals, %i[account_id pipeline_id created_at], 'index_crm_deals_active_on_account_pipeline_created'],
    # Forecast buckets by `expected_close_on` over the open deals only.
    [:crm_deals, %i[account_id pipeline_id expected_close_on], 'index_crm_deals_active_on_account_pipeline_close_on']
  ].freeze

  def up
    INDEXES.each do |table, columns, name|
      add_index table, columns, name: name, where: 'archived_at IS NULL', algorithm: :concurrently, if_not_exists: true
    end

    # `Crm::Reports::FunnelService` builds its `visits` CTE with a DISTINCT over
    # (deal_id, to_stage_id); without the second column it reads the heap for every transition row.
    add_index :crm_stage_transitions, [:deal_id, :to_stage_id],
              name: 'index_crm_stage_transitions_on_deal_id_and_to_stage', algorithm: :concurrently, if_not_exists: true

    # `Crm::Deal::NEXT_ACTIVITY_AT_SQL` is a correlated subquery evaluated once per card of the
    # page: MIN(due_at) for a deal among the activities nobody completed. Partial on
    # `completed_at IS NULL` so the 25 lookups of a board column are index-only.
    add_index :crm_activities, [:deal_id, :due_at],
              name: 'index_crm_activities_pending_on_deal_id_and_due_at', where: 'completed_at IS NULL',
              algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :crm_activities, name: 'index_crm_activities_pending_on_deal_id_and_due_at',
                                  algorithm: :concurrently, if_exists: true
    remove_index :crm_stage_transitions, name: 'index_crm_stage_transitions_on_deal_id_and_to_stage',
                                         algorithm: :concurrently, if_exists: true

    INDEXES.each do |table, _columns, name|
      remove_index table, name: name, algorithm: :concurrently, if_exists: true
    end
  end
end
