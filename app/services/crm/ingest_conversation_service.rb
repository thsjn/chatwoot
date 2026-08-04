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
  # The dedupe window, the advisory lock and the entry position are shared with the external lead
  # ingestion, so a lead posted to the API lands on the very same card this service would reuse.
  include Crm::DealDedupe

  DEFAULT_CURRENCY = 'BRL'.freeze

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

    # The single gate of the asynchronous ingestion: `CrmListener` -> `Crm::IngestConversationJob`,
    # `Crm::BackfillJob` and any console call all land here, so an account with the CRM module off
    # never gets a card out of a conversation, however the ingestion was triggered.
    return @result unless @conversation.account.crm_kanban?

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
    lock_dedupe_key!(account_id: @conversation.account_id, pipeline: pipeline, contact_id: @conversation.contact_id)
    deal = deduplicated_deal(pipeline: pipeline, contact_id: @conversation.contact_id)

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

    if deduplicated_deal(pipeline: pipeline, contact_id: @conversation.contact_id).present? || @simulated_deal_keys&.include?(key)
      @result[:linked] += 1
    else
      @simulated_deal_keys&.add(key)
      @result[:created] += 1
    end
  end

  # The unique index on `crm_deal_conversations` only protects the LINK, not the card, so the
  # read-then-write of the dedupe is serialised by the advisory lock in Crm::DealDedupe.
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
      position: next_deal_position(account_id: @conversation.account_id, stage: stage),
      last_activity_at: Time.current,
      creation_automated: true
    )
  end

  def link_conversation(deal, is_origin:)
    Crm::DealConversation.create!(deal: deal, conversation: @conversation, is_origin: is_origin)
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
