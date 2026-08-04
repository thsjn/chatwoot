class Crm::PipelinePolicy < ApplicationPolicy
  # Pipelines are account configuration: agents work inside them, administrators shape them.
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  # Archiving retires a funnel the whole account works on, so it sits with the other shaping
  # actions rather than with the day-to-day board operations.
  def archive?
    @account_user.administrator?
  end

  def unarchive?
    @account_user.administrator?
  end
end
