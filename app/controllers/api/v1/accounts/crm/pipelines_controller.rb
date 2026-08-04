class Api::V1::Accounts::Crm::PipelinesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy]
  before_action :authorize_pipeline

  def index
    @pipelines = pipelines.ordered
  end

  def show; end

  def create
    @pipeline = pipelines.create!(permitted_params)
  end

  def update
    @pipeline.update!(permitted_params)
  end

  # `dependent: :restrict_with_error` on the deals association turns a pipeline still in use
  # into a validation error instead of an exception, so it is surfaced as a 422.
  def destroy
    return render_could_not_create_error(@pipeline.errors.full_messages.join(', ')) unless @pipeline.destroy

    head :ok
  end

  private

  def pipelines
    Crm::Pipeline.where(account_id: Current.account.id)
  end

  def fetch_pipeline
    @pipeline = pipelines.find(params[:id])
  end

  def authorize_pipeline
    authorize(@pipeline || Crm::Pipeline)
  end

  def permitted_params
    params.require(:pipeline).permit(
      :name, :description, :position, :is_default,
      settings: [:janela_dedupe_dias, :exige_proxima_atividade, :moeda_padrao, :restrito_por_owner, { inbox_ids: [] }]
    )
  end
end
