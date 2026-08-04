class Api::V1::Accounts::Crm::LostReasonsController < Api::V1::Accounts::BaseController
  before_action :fetch_lost_reason, only: [:show, :update, :destroy]
  before_action :authorize_lost_reason

  def index
    @lost_reasons = lost_reasons.ordered
  end

  def show; end

  def create
    @lost_reason = lost_reasons.create!(permitted_params)
  end

  def update
    @lost_reason.update!(permitted_params)
  end

  # Deals keep pointing at nothing (`dependent: :nullify`) instead of blocking the deletion,
  # so a reason retired from the list can be removed at any time.
  def destroy
    @lost_reason.destroy!
    head :ok
  end

  private

  def lost_reasons
    Crm::LostReason.where(account_id: Current.account.id)
  end

  def fetch_lost_reason
    @lost_reason = lost_reasons.find(params[:id])
  end

  def authorize_lost_reason
    authorize(@lost_reason || Crm::LostReason)
  end

  def permitted_params
    params.require(:lost_reason).permit(:name, :position, :active)
  end
end
