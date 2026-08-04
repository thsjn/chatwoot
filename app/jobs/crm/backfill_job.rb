# Applies the same ingestion rules of `Crm::IngestConversationJob` to the conversations that
# already existed when the account configured `settings['inbox_ids']` on a pipeline.
#
# Defaults to `dry_run: true`: the first run only reports how many cards WOULD be created and how
# many conversations WOULD be linked, per inbox. Turning ingestion on for a busy inbox is a
# destructive-looking operation on the board, so the preview has to be the default.
#
#   Crm::BackfillJob.perform_now(Account.find(1))                                   # preview
#   Crm::BackfillJob.perform_now(Account.find(1), dry_run: false, window_days: 30)  # for real
class Crm::BackfillJob < ApplicationJob
  queue_as :low

  DEFAULT_WINDOW_DAYS = 90
  BATCH_SIZE = 200

  def perform(account, dry_run: true, window_days: DEFAULT_WINDOW_DAYS)
    @account = account
    @dry_run = dry_run
    @report = { dry_run: dry_run, window_days: window_days, totals: { created: 0, linked: 0 }, by_inbox: {} }
    # Only used by the preview: a real run reads the deals it just wrote, a dry run has to remember
    # the cards it pretended to create so the second conversation of a contact counts as a link.
    @simulated_deal_keys = Set.new if dry_run

    inbox_ids = configured_inbox_ids
    process(inbox_ids, window_days) if inbox_ids.any?

    log_report
    @report
  end

  private

  # Union of the inboxes wired to any active pipeline of the account. Ingestion is off by default,
  # so this is normally empty and the backfill is a no-op.
  def configured_inbox_ids
    Crm::Pipeline.active.where(account_id: @account.id).pluck(:settings).flat_map { |settings| settings['inbox_ids'] }.compact.map(&:to_i).uniq
  end

  # `find_each` batches by primary key, which also processes the conversations in chronological
  # order: the oldest one opens the card and the newer ones are linked to it.
  def process(inbox_ids, window_days)
    Conversation.where(account_id: @account.id, inbox_id: inbox_ids)
                .where(created_at: window_days.days.ago..)
                .find_each(batch_size: BATCH_SIZE) do |conversation|
      result = ingest(conversation)
      accumulate(conversation.inbox_id, result)
    end
  end

  def ingest(conversation)
    Crm::IngestConversationService.new(
      conversation: conversation,
      dry_run: @dry_run,
      simulated_deal_keys: @simulated_deal_keys
    ).perform
  end

  def accumulate(inbox_id, result)
    return if result[:created].zero? && result[:linked].zero?

    bucket = @report[:by_inbox][inbox_id] ||= { created: 0, linked: 0 }
    bucket[:created] += result[:created]
    bucket[:linked] += result[:linked]
    @report[:totals][:created] += result[:created]
    @report[:totals][:linked] += result[:linked]
  end

  def log_report
    Rails.logger.info(
      "[Crm::BackfillJob] account=#{@account.id} dry_run=#{@dry_run} window_days=#{@report[:window_days]} " \
      "created=#{@report[:totals][:created]} linked=#{@report[:totals][:linked]} by_inbox=#{@report[:by_inbox]}"
    )
  end
end
