class Crm::StagePolicy < ApplicationPolicy
  # Stages are part of the pipeline configuration, so they follow the pipeline rules.
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
end
