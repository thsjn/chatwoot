class Api::V1::Accounts::Crm::SourcesController < Api::V1::Accounts::BaseController
  before_action :fetch_source, only: [:show, :update, :destroy]
  before_action :authorize_source

  # Same rule as the lost reasons: a source the account turned off is history on the deals that
  # already carry it, but it must not show up in the selects as if it were still usable. The
  # administration screen asks for the whole list through `include_inactive`.
  def index
    scope = sources.order(:name)
    scope = scope.active unless include_inactive?
    @sources = scope
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

  def include_inactive?
    ActiveModel::Type::Boolean.new.cast(params[:include_inactive])
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
