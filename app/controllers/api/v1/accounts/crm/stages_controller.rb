class Api::V1::Accounts::Crm::StagesController < Api::V1::Accounts::BaseController
  include Crm::DealFilterable

  before_action :fetch_pipeline
  before_action :fetch_stage, only: [:show, :update, :destroy]
  before_action :authorize_stage
  before_action :set_stage_aggregates, only: [:index, :show, :create, :update]

  def index
    @stages = @pipeline.stages.ordered
  end

  def show; end

  def create
    @stage = @pipeline.stages.create!(permitted_params.merge(account_id: Current.account.id))
  end

  def update
    @stage.update!(permitted_params)
  end

  # `dependent: :restrict_with_error` on the deals association turns a stage still holding
  # deals into a validation error instead of an exception, so it is surfaced as a 422.
  def destroy
    return render_could_not_create_error(@stage.errors.full_messages.join(', ')) unless @stage.destroy

    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = Crm::Pipeline.where(account_id: Current.account.id).find(params[:pipeline_id])
  end

  def fetch_stage
    @stage = @pipeline.stages.find(params[:id])
  end

  # Two grouped queries covering every stage of the pipeline: the board header needs the totals of
  # the whole stage, and one query per column would not scale.
  #
  # The column header publishes both numbers on purpose. `deals_count` is the total of the stage
  # and is what the WIP limit is about — the limit exists over the whole column, so hiding cards
  # behind a filter must never make a full column look free. `filtered_deals_count` matches the
  # cards the board is actually rendering, so a filtered column does not show a header that
  # contradicts its own content.
  #
  # The second query only runs when the request carries board filters: without them the filtered
  # scope IS the stage scope, so the answer would be the stage total under another name — and the
  # board reads the presence of these fields as "there is a filter on".
  def set_stage_aggregates
    @stage_aggregates = Crm::StageAggregatesService.new(pipeline: @pipeline, deals_scope: policy_scope(Crm::Deal).open).perform
    return unless board_filters_present?

    @filtered_stage_aggregates = Crm::StageAggregatesService.new(pipeline: @pipeline, deals_scope: filtered_deals_scope).perform
  end

  # Same filters as the deals index, and the same default: the board only lists the deals still in
  # play unless it explicitly asks for another status.
  def filtered_deals_scope
    scope = apply_deal_filters(policy_scope(Crm::Deal))
    filtering_by_status? ? scope : scope.open
  end

  def authorize_stage
    authorize(@stage || Crm::Stage)
  end

  def permitted_params
    params.require(:stage).permit(:name, :category, :position, :color, :probability, :rotting_days, :wip_limit, :is_entry)
  end
end
