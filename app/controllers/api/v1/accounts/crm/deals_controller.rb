class Api::V1::Accounts::Crm::DealsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :fetch_deal, only: [:show, :update, :destroy, :move]
  before_action :authorize_deal, except: [:move]
  before_action :set_current_page, only: [:index]

  def index
    deals = filtered_deals
    @deals_count = deals.count
    @deals = deals.ordered.with_next_activity
                  .includes(:contact, :owner, :team, :stage, :source, :lost_reason, deal_conversations: { conversation: :inbox })
                  .page(@current_page).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @deal = Crm::Deal.new(permitted_params.merge(account_id: Current.account.id))
    @deal.stage ||= @deal.pipeline&.entry_stage
    @deal.save!
  end

  def update
    @deal.update!(permitted_params)
  end

  # Deals are never deleted: closing a card keeps the pipeline history intact, so `destroy`
  # archives it instead.
  def destroy
    @deal.archive!
    head :ok
  end

  def move
    authorize @deal, :update?

    Crm::MoveDealService.new(
      deal: @deal, stage: destination_stage, user: Current.user, position: move_params[:position],
      lock_version: move_params[:lock_version], lost_reason_id: move_params[:lost_reason_id]
    ).perform
    render 'show'
  rescue Crm::MoveDealService::MoveError => e
    render json: { error_code: e.error_code }, status: :unprocessable_entity
  rescue ActiveRecord::StaleObjectError
    @deal.reload
    render 'show', status: :conflict
  end

  private

  def deals
    Crm::Deal.where(account_id: Current.account.id)
  end

  def fetch_deal
    @deal = deals.includes(deal_conversations: { conversation: :inbox }).find(params[:id])
  end

  def authorize_deal
    authorize(@deal || Crm::Deal)
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  # `policy_scope` carries the `restrito_por_owner` rule, so the visibility filtering is never
  # rebuilt here: this method only applies the board filters on top of it.
  def filtered_deals
    scope = policy_scope(Crm::Deal).active
    scope = scope.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    scope = scope.where(stage_id: params[:stage_id]) if params[:stage_id].present?
    scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    scope = scope.where(source_id: params[:source_id]) if params[:source_id].present?
    scope = scope.where(status: params[:status]) if Crm::Deal.statuses.key?(params[:status])
    scope = scope.where('crm_deals.title ILIKE :search', search: "%#{params[:q].strip}%") if params[:q].present?
    scope
  end

  def destination_stage
    @deal.pipeline.stages.find(move_params[:stage_id])
  end

  def move_params
    params.permit(:stage_id, :position, :lock_version, :lost_reason_id)
  end

  # `status` is derived from the stage category and `stage_id`/`pipeline_id` are only accepted
  # on create: moving a card has to go through `move`, which records the transition.
  def permitted_params
    params.require(:deal).permit(
      :title, :contact_id, :owner_id, :team_id, :source_id, :source_inbox_id,
      :value_cents, :currency, :expected_close_on, :position,
      *creation_only_params, custom_attributes: {}, utm: {}
    )
  end

  # `lost_reason_id` is not updatable here on purpose: it belongs to the transition into a lost
  # stage. Accepting it on `update` would let a client pre-fill the reason on an open deal and
  # then slip past the `lost_reason_required` check on `move`.
  def creation_only_params
    action_name == 'create' ? [:pipeline_id, :stage_id, :lost_reason_id] : []
  end
end
