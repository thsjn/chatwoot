class Api::V1::Accounts::Crm::DealsController < Api::V1::Accounts::Crm::BaseController
  include Crm::DealFilterable

  RESULTS_PER_PAGE = 25

  # The card renders the contact and owner avatars through `Avatarable#avatar_url`, which asks
  # ActiveStorage whether an avatar is attached: without preloading the attachment and its blob
  # that is two extra queries per card, so a full column costs fifty round trips nobody sees in
  # the SQL of the listing itself. Same pattern as `ConversationFinder`.
  INDEX_INCLUDES = [
    :team, :stage, :source, :lost_reason,
    { contact: { avatar_attachment: :blob } },
    { owner: { avatar_attachment: :blob } },
    { deal_conversations: { conversation: :inbox } }
  ].freeze

  before_action :fetch_deal, only: [:show, :update, :destroy, :move, :unarchive]
  before_action :authorize_deal, except: [:move]
  before_action :set_current_page, only: [:index]

  helper_method :accessible_conversation?

  def index
    deals = filtered_deals
    @deals_count = deals.count
    @deals = deals.ordered.with_next_activity.includes(*INDEX_INCLUDES).page(@current_page).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @deal = Crm::Deal.new(permitted_params.merge(account_id: Current.account.id))
    @deal.stage ||= @deal.pipeline&.entry_stage
    # Creating a card is the first transition of the funnel and is credited to whoever did it.
    @deal.creation_user = Current.user
    @deal.save!
  end

  # `lock_version` is optional: the drawer sends the version of the card it rendered, so two agents
  # editing the same deal collide with a 409 (carrying the current deal, like `move` does) instead
  # of silently overwriting each other. Callers that do not track a version — the internal ones and
  # anything scripted against the API — keep the previous last-write-wins behaviour.
  def update
    @deal.lock_version = params[:lock_version] if params[:lock_version].present?
    @deal.update!(permitted_params)
  rescue ActiveRecord::StaleObjectError
    @deal.reload
    render 'show', status: :conflict
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

  # A deal links conversations from whichever inbox the lead arrived on, but a conversation is only
  # visible to an agent who belongs to its inbox or to its team (`ConversationPolicy#show?`).
  # Publishing the whole link list on the card would leak the existence, `display_id`, status and
  # inbox of conversations the agent cannot open — the deal being visible says nothing about the
  # inbox behind it. Administrators keep seeing everything: `assigned_inboxes` already resolves to
  # every inbox of the account for them.
  def accessible_conversation?(conversation)
    accessible_inbox_ids.include?(conversation.inbox_id) ||
      (conversation.team_id.present? && accessible_team_ids.include?(conversation.team_id))
  end

  def accessible_inbox_ids
    @accessible_inbox_ids ||= Current.user.assigned_inboxes.pluck(:id)
  end

  def accessible_team_ids
    @accessible_team_ids ||= Current.user.teams.where(account_id: Current.account.id).pluck(:id)
  end

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
      :value_cents, :currency, :expected_close_on,
      *creation_only_params, custom_attributes: {}, utm: {}
    )
  end

  # `lost_reason_id` is not updatable here on purpose: it belongs to the transition into a lost
  # stage. Accepting it on `update` would let a client pre-fill the reason on an open deal and
  # then slip past the `lost_reason_required` check on `move`.
  # `position` is on the same list: it is the rank of the card inside its column, and reordering
  # is a move — accepting it here would let a client rewrite the board order without going through
  # `Crm::MoveDealService` (no optimistic lock check, no `crm_deal.moved` semantics).
  def creation_only_params
    action_name == 'create' ? [:pipeline_id, :stage_id, :lost_reason_id, :position] : []
  end
end
