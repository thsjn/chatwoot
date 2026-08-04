# The rule that keeps the board holding one card per CONTACT's business instead of one card per
# incoming event. Shared by every ingestion path (conversations from an inbox, leads posted by an
# external system) so a lead arriving through the API collapses into the same card a WhatsApp
# conversation of the same contact would have opened.
module Crm::DealDedupe
  DEFAULT_DEDUPE_WINDOW_DAYS = 30
  DEDUPE_LOCK_PREFIX = 'crm_ingest_deal'.freeze

  private

  # The dedupe below reads before it writes, so two events for the same contact arriving together
  # (routine on WhatsApp, where a job runs per conversation, and on a landing page that double
  # submits) would both find no deal and both create one. The advisory lock serialises the whole
  # read-then-write per (pipeline, contact): it is transaction scoped, so it is released on
  # COMMIT/ROLLBACK with no unlock to leak, and it blocks nothing but another ingestion of the very
  # same pair.
  # The key has to be a single 64 bit integer, so it is the CRC32 of the identifying triple —
  # account included, so two accounts never share a lock slot.
  def lock_dedupe_key!(account_id:, pipeline:, contact_id:)
    lock_key = "#{DEDUPE_LOCK_PREFIX}_#{account_id}_#{pipeline.id}_#{contact_id}"

    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?)', Zlib.crc32(lock_key)])
    )
  end

  # The dedupe window is measured from now, not from the event timestamp: a backfill run therefore
  # collapses the whole history of a contact into a single card, which is the intent (one card per
  # business, not one per conversation).
  def deduplicated_deal(pipeline:, contact_id:)
    cutoff = dedupe_window_days(pipeline).days.ago

    pipeline.deals
            .active
            .open
            .where(contact_id: contact_id)
            .where('crm_deals.created_at >= :cutoff OR crm_deals.updated_at >= :cutoff', cutoff: cutoff)
            .order(created_at: :desc)
            .first
  end

  def dedupe_window_days(pipeline)
    days = pipeline.settings['janela_dedupe_dias'].to_i
    days.positive? ? days : DEFAULT_DEDUPE_WINDOW_DAYS
  end

  # Same rule as Crm::MoveDealService: the card lands at the bottom of the entry column and only
  # active deals count, so an archived card never pushes new ones further down.
  def next_deal_position(account_id:, stage:)
    (Crm::Deal.where(account_id: account_id, stage_id: stage.id).active.maximum(:position) || 0) + Crm::Deal::POSITION_GAP
  end
end
