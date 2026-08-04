class Api::V1::Accounts::Crm::DealsController < Api::V1::Accounts::BaseController
  include Crm::DealFilterable

  RESULTS_PER_PAGE = 25

  before_action :fetch_deal, only: [:show, :update, :destroy, :move, :unarchive]
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
    # Creating a card is the first transition of the funnel and is credited to whoever did it.
    @deal.creation_user = Current.user
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

  # Archiving is reversible: without this the card would leave the board for good, and the only
  # way back would be the database. The archived cards are reachable through `index` with
  # `archived=true`.
  def unarchive
    @deal.unarchive!
    render 'show'
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
  # `archived=true` lists the archived cards instead of the board ones, which is how the UI offers
  # a card back to be restored through `unarchive`.
  def filtered_deals
    scope = policy_scope(Crm::Deal)
    scope = ActiveModel::Type::Boolean.new.cast(params[:archived]) ? scope.archived : scope.active
    apply_deal_filters(scope)
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
