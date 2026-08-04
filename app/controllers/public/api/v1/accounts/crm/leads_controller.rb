# External entry point of the funnel: a landing page form, an n8n flow or any HTTP client posts a
# lead here and it becomes a card.
#
# There is no user session. The caller is the `Crm::Source` whose token it presents, and that source
# is looked up INSIDE the account of the URL, so a token that is perfectly valid for another account
# is rejected exactly like a made up one.
class Public::Api::V1::Accounts::Crm::LeadsController < PublicController
  # Included before the token check on purpose: with the module off the endpoint answers 404 to
  # every caller, so a valid token cannot be used to tell an account that never enabled the CRM
  # apart from one that does not exist.
  include Crm::ModuleEnabled

  TOKEN_HEADER = 'HTTP_X_CRM_SOURCE_TOKEN'.freeze

  before_action :authenticate_source
  before_action :validate_contact_identification

  def create
    result = ::Crm::IngestLeadService.new(source: @source, params: lead_params.to_h.symbolize_keys).perform

    log_ingestion(result)

    render json: {
      deal_id: result[:deal].id,
      contact_id: result[:deal].contact_id,
      pipeline_id: result[:deal].pipeline_id,
      status: result[:created] ? 'created' : 'deduplicated'
    }, status: result[:created] ? :created : :ok
  rescue ::Crm::IngestLeadService::ConfigurationError => e
    render json: { error: I18n.t("crm.lead_ingestion.#{e.code}"), code: e.code }, status: :unprocessable_entity
  end

  private

  # There is no session here, so the account of the gate is the one in the URL — the same one the
  # source is looked up inside.
  def crm_module_account
    @crm_module_account ||= Account.find_by(id: params[:account_id])
  end

  # `Authorization: Bearer <token>` is accepted as well because it is what most no-code HTTP nodes
  # offer out of the box, but the dedicated header is the documented one.
  def presented_token
    @presented_token ||= request.get_header(TOKEN_HEADER).presence || request.headers['Authorization'].to_s[/\ABearer (.+)\z/, 1]
  end

  def authenticate_source
    @source = ::Crm::Source.authenticate(account_id: params[:account_id], token: presented_token)

    return if @source.present?

    render json: { error: I18n.t('crm.lead_ingestion.invalid_token') }, status: :unauthorized
  end

  # The contact has to be identifiable, otherwise every lead of the account would collapse onto a
  # single anonymous card.
  def validate_contact_identification
    return if lead_params[:email].present? || lead_params[:phone_number].present?

    render json: { error: I18n.t('crm.lead_ingestion.contact_required'), code: 'contact_required' }, status: :unprocessable_entity
  end

  # Anything outside this list is dropped: a public endpoint must not be able to set the owner, the
  # stage or the status of a card.
  def lead_params
    @lead_params ||= params.permit(:name, :email, :phone_number, :title, :value, :pipeline_id, utm: ::Crm::IngestLeadService::UTM_KEYS)
  end

  # The lead itself carries PII (name, email, phone) and none of it belongs in the application log:
  # what operations needs is which source fed which card, and whether it opened one or hit the
  # dedupe.
  def log_ingestion(result)
    Rails.logger.info(
      "[CRM][LEAD] account=#{@source.account_id} source=#{@source.id} pipeline=#{result[:deal].pipeline_id} " \
      "deal=#{result[:deal].id} created=#{result[:created]}"
    )
  end
end
