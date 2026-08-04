class Api::V1::Accounts::Crm::ActivitiesController < Api::V1::Accounts::BaseController
  before_action :fetch_deal
  before_action :fetch_activity, only: [:show, :update, :destroy]
  before_action :authorize_activity

  def index
    @activities = @deal.activities.chronological.includes(:user)
  end

  def show; end

  def create
    @activity = @deal.activities.create!(permitted_params.merge(account_id: Current.account.id, user_id: Current.user.id))
  end

  def update
    @activity.update!(permitted_params)
  end

  def destroy
    @activity.destroy!
    head :ok
  end

  private

  # The timeline follows the deal, so the deal policy (which carries `restrito_por_owner`)
  # is what decides whether these activities are visible at all.
  def fetch_deal
    @deal = Crm::Deal.where(account_id: Current.account.id).find(params[:deal_id])
    authorize @deal, :show?
  end

  def fetch_activity
    @activity = @deal.activities.find(params[:id])
  end

  def authorize_activity
    authorize(Crm::Activity)
  end

  def permitted_params
    params.require(:activity).permit(:kind, :content, :due_at, :completed_at)
  end
end
