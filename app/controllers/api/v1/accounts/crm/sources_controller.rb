class Api::V1::Accounts::Crm::SourcesController < Api::V1::Accounts::BaseController
  before_action :fetch_source, only: [:show, :update, :destroy]
  before_action :authorize_source

  def index
    @sources = sources.order(:name)
  end

  def show; end

  def create
    @source = sources.create!(permitted_params)
  end

  def update
    @source.update!(permitted_params)
  end

  def destroy
    @source.destroy!
    head :ok
  end

  private

  def sources
    Crm::Source.where(account_id: Current.account.id)
  end

  def fetch_source
    @source = sources.find(params[:id])
  end

  def authorize_source
    authorize(@source || Crm::Source)
  end

  def permitted_params
    params.require(:source).permit(:name, :kind, :identifier, :active, :inbox_id)
  end
end
