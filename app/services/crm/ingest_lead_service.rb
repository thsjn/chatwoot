# Turns a lead posted by an external system (a landing page form, an n8n flow, any HTTP client
# holding the token of a `Crm::Source`) into a card of the CRM funnel.
#
# It is the sibling of `Crm::IngestConversationService`: the two share `Crm::DealDedupe`, so a lead
# for a contact who already has an open card inside the dedupe window updates that card instead of
# opening a second one — exactly like a new WhatsApp conversation would.
class Crm::IngestLeadService
  include Crm::DealDedupe

  DEFAULT_CURRENCY = 'BRL'.freeze

  # Only the standard campaign parameters are stored. Anything else the caller sends is dropped, so
  # a public endpoint cannot be used to stuff arbitrary jsonb into the account's deals.
  UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_term utm_content].freeze

  # Raised when the payload is well formed but the account is not set up to receive it. The caller
  # turns it into a 422 carrying `code`, which is what tells the integrator what to fix.
  class ConfigurationError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end

  # @param source [Crm::Source] the credentialed source the token authenticated.
  # @param params [Hash] symbol keyed, already permitted by the controller.
  def initialize(source:, params:)
    @source = source
    @account = source.account
    @params = params
  end

  # Returns { deal: <Crm::Deal>, created: <true when a new card was opened> }.
  def perform
    pipeline = resolve_pipeline!
    inbox = resolve_inbox!

    ActiveRecord::Base.transaction do
      contact = find_or_create_contact(inbox)
      lock_dedupe_key!(account_id: @account.id, pipeline: pipeline, contact_id: contact.id)

      existing = deduplicated_deal(pipeline: pipeline, contact_id: contact.id)
      next { deal: touch_deal(existing), created: false } if existing.present?

      { deal: create_deal(pipeline, contact), created: true }
    end
  end

  private

  # An archived pipeline is retired: it is out of the board and out of every ingestion path, so a
  # token pointing at one is a configuration the integrator has to fix rather than a silent no-op.
  def resolve_pipeline!
    scope = Crm::Pipeline.active.where(account_id: @account.id)

    pipeline = if @params[:pipeline_id].present?
                 scope.find_by(id: @params[:pipeline_id])
               else
                 scope.find_by(is_default: true) || scope.ordered.first
               end

    raise ConfigurationError, :pipeline_not_found if pipeline.blank?
    raise ConfigurationError, :pipeline_without_stages if pipeline.entry_stage.blank?

    pipeline
  end

  # The contact is built by the standard `ContactInboxWithContactBuilder`, which is what dedupes it
  # by identifier/email/phone and keeps the channel bookkeeping right — and that builder needs an
  # inbox. Linking the source to one (the `inbox_id` the sources screen already asks for) is
  # therefore part of credentialing it, and a source without an inbox fails loudly instead of
  # creating half-registered contacts.
  def resolve_inbox!
    raise ConfigurationError, :source_without_inbox if @source.inbox.blank?

    @source.inbox
  end

  def find_or_create_contact(inbox)
    ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: {
        name: @params[:name].presence,
        email: @params[:email].presence,
        phone_number: @params[:phone_number].presence
      }.compact
    ).perform.contact
  end

  def create_deal(pipeline, contact)
    stage = pipeline.entry_stage

    Crm::Deal.create!(
      account_id: @account.id,
      pipeline: pipeline,
      stage: stage,
      contact: contact,
      title: deal_title(contact),
      value_cents: value_cents,
      currency: pipeline.settings['moeda_padrao'].presence || DEFAULT_CURRENCY,
      source: @source,
      source_inbox_id: @source.inbox_id,
      utm: utm,
      position: next_deal_position(account_id: @account.id, stage: stage),
      last_activity_at: Time.current,
      creation_automated: true
    )
  end

  # A deduplicated lead is still a signal: the card is bumped so it does not rot, and the campaign
  # data of the FIRST touch is kept — overwriting it would rewrite the attribution of the deal.
  def touch_deal(deal)
    deal.update!(last_activity_at: Time.current)
    deal
  end

  def deal_title(contact)
    @params[:title].presence || contact.name.presence || contact.email.presence || contact.phone_number.presence ||
      I18n.t('crm.deal.default_title', id: contact.id)
  end

  # `value` arrives in the currency's main unit (149.90), the column stores cents.
  def value_cents
    (@params[:value].to_s.to_d * 100).round
  end

  def utm
    return {} if @params[:utm].blank?

    @params[:utm].to_h.stringify_keys.slice(*UTM_KEYS).compact_blank
  end
end
