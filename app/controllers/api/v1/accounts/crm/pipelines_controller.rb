class Api::V1::Accounts::Crm::PipelinesController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy, :archive, :unarchive]
  before_action :authorize_pipeline

  # Same rule as the sources and the lost reasons: an archived pipeline is retired, so it leaves the
  # board selector and the automatic ingestion but stays reachable — the administration screen asks
  # for the whole list through `include_archived` to be able to restore it.
  def index
    scope = pipelines
    scope = scope.active unless include_archived?
    @pipelines = scope.ordered
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

  # Retiring a funnel that is in use. `destroy` is refused while it holds deals, so this is the only
  # way to take one off the board — and it deliberately leaves the deals untouched: the history of a
  # closed funnel is still the history of the account, and unarchiving brings the board back intact.
  def archive
    @pipeline.archive!
  end

  def unarchive
    @pipeline.unarchive!
  end

  private

  def pipelines
    Crm::Pipeline.where(account_id: Current.account.id)
  end

  def include_archived?
    ActiveModel::Type::Boolean.new.cast(params[:include_archived])
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
