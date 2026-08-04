# Turns a Chatwoot conversation into a card of the CRM funnel.
#
# Ingestion is opt-in: a pipeline only takes a conversation when its `settings['inbox_ids']`
# lists the conversation inbox. The seeder ships that key empty, so nothing is ingested until
# the account explicitly picks the inboxes.
#
# The card stands for the CONTACT's business, not for a single conversation: when the contact
# already has an open deal inside the dedupe window, the new conversation is linked to that deal
# instead of opening a second card.
class Crm::IngestConversationService
  DEFAULT_DEDUPE_WINDOW_DAYS = 30
  DEFAULT_CURRENCY = 'BRL'.freeze
  DEDUPE_LOCK_PREFIX = 'crm_ingest_deal'.freeze

  # `dry_run` powers the backfill preview: nothing is written and the caller only gets the counts.
  # `simulated_deal_keys` is the set of "pipeline_id:contact_id" pairs a dry run already counted as
  # created, so a contact with several conversations reports one card plus N links, not N cards.
  def initialize(conversation:, dry_run: false, simulated_deal_keys: nil)
    @conversation = conversation
    @dry_run = dry_run
    @simulated_deal_keys = simulated_deal_keys
  end

  # Returns { created: <deals>, linked: <conversations attached to an existing deal> }.
  def perform
    @result = { created: 0, linked: 0 }

    # Idempotency: the job is retried by Sidekiq and the backfill may run over conversations the
    # listener already ingested. A conversation that already belongs to a deal is never touched
    # again, so a second run is a no-op.
    return @result if already_linked?

    pipelines = matching_pipelines
    return @result if pipelines.empty?

    if @dry_run
      pipelines.each { |pipeline| simulate(pipeline) }
      return @result
    end

    # One transaction for every matching pipeline: a failure halfway through rolls back, so the
    # `already_linked?` guard above still sees a clean state on the retry.
    ActiveRecord::Base.transaction { pipelines.each { |pipeline| ingest_into(pipeline) } }

    @result
  end

  private

  def already_linked?
    Crm::DealConversation.exists?(conversation_id: @conversation.id)
  end

  # `settings['inbox_ids']` is jsonb, so the inbox id may have been stored as a number (JSON API)
  # or as a string (form-encoded params). Both shapes are matched with the jsonb containment
  # operator, which uses the GIN-able `settings` column instead of loading every pipeline.
  def matching_pipelines
    Crm::Pipeline.active
                 .where(account_id: @conversation.account_id)
                 .where(
                   "crm_pipelines.settings -> 'inbox_ids' @> :number OR crm_pipelines.settings -> 'inbox_ids' @> :string",
                   number: [@conversation.inbox_id].to_json,
                   string: [@conversation.inbox_id.to_s].to_json
                 )
                 .ordered
                 .to_a
  end

  def ingest_into(pipeline)
    lock_dedupe_key!(pipeline)
    deal = deduplicated_deal(pipeline)

    if deal.present?
      link_conversation(deal, is_origin: false)
      deal.update!(last_activity_at: Time.current)
      @result[:linked] += 1
    else
      link_conversation(create_deal(pipeline), is_origin: true)
      @result[:created] += 1
    end
  end

  def simulate(pipeline)
    key = "#{pipeline.id}:#{@conversation.contact_id}"

    if deduplicated_deal(pipeline).present? || @simulated_deal_keys&.include?(key)
      @result[:linked] += 1
    else
      @simulated_deal_keys&.add(key)
      @result[:created] += 1
    end
  end

  # The dedupe below reads before it writes, and the unique index on `crm_deal_conversations`
  # only protects the LINK, not the card: two conversations of the same contact arriving together
  # (routine on WhatsApp, where a job runs per conversation) would both find no deal and both
  # create one. The advisory lock serialises the whole read-then-write per (pipeline, contact):
  # it is transaction scoped, so it is released on COMMIT/ROLLBACK with no unlock to leak, and it
  # blocks nothing but another ingestion of the very same pair.
  # The key has to be a single 64 bit integer, so it is the CRC32 of the identifying triple —
  # account included, so two accounts never share a lock slot.
  def lock_dedupe_key!(pipeline)
    lock_key = "#{DEDUPE_LOCK_PREFIX}_#{@conversation.account_id}_#{pipeline.id}_#{@conversation.contact_id}"

    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?)', Zlib.crc32(lock_key)])
    )
  end

  # The dedupe window is measured from now, not from the conversation timestamp: a backfill run
  # therefore collapses the whole history of a contact into a single card, which is the intent
  # (one card per business, not one per conversation).
  def deduplicated_deal(pipeline)
    cutoff = dedupe_window_days(pipeline).days.ago

    pipeline.deals
            .active
            .open
            .where(contact_id: @conversation.contact_id)
            .where('crm_deals.created_at >= :cutoff OR crm_deals.updated_at >= :cutoff', cutoff: cutoff)
            .order(created_at: :desc)
            .first
  end

  def dedupe_window_days(pipeline)
    days = pipeline.settings['janela_dedupe_dias'].to_i
    days.positive? ? days : DEFAULT_DEDUPE_WINDOW_DAYS
  end

  def create_deal(pipeline)
    stage = pipeline.entry_stage

    Crm::Deal.create!(
      account_id: @conversation.account_id,
      pipeline: pipeline,
      stage: stage,
      contact_id: @conversation.contact_id,
      title: deal_title,
      currency: pipeline.settings['moeda_padrao'].presence || DEFAULT_CURRENCY,
      source_id: inbox_source&.id,
      source_inbox_id: @conversation.inbox_id,
      position: next_position(stage),
      last_activity_at: Time.current,
      creation_automated: true
    )
  end

  def link_conversation(deal, is_origin:)
    Crm::DealConversation.create!(deal: deal, conversation: @conversation, is_origin: is_origin)
  end

  # Same rule as Crm::MoveDealService: the card lands at the bottom of the entry column and only
  # active deals count, so an archived card never pushes new ones further down.
  def next_position(stage)
    (Crm::Deal.where(account_id: @conversation.account_id, stage_id: stage.id).active.maximum(:position) || 0) + Crm::Deal::POSITION_GAP
  end

  def inbox_source
    return @inbox_source if defined?(@inbox_source)

    @inbox_source = Crm::Source.kind_inbox.find_by(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id)
  end

  # Contacts created from a channel often have an empty `name`, so the title falls back to whatever
  # identifies the person on the board before an agent renames the card.
  def deal_title
    contact = @conversation.contact

    contact.name.presence || contact.email.presence || contact.phone_number.presence ||
      I18n.t('crm.deal.default_title', id: contact.id)
  end
end
