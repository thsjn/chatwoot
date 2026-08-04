class Api::V1::Accounts::Crm::StagesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline
  before_action :fetch_stage, only: [:show, :update, :destroy]
  before_action :authorize_stage

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

  def authorize_stage
    authorize(@stage || Crm::Stage)
  end

  def permitted_params
    params.require(:stage).permit(:name, :category, :position, :color, :probability, :rotting_days, :wip_limit, :is_entry)
  end
end
