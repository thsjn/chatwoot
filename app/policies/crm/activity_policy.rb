class Crm::ActivityPolicy < ApplicationPolicy
  # Activities are the deal timeline, so visibility follows the deal: controllers authorize
  # the parent deal (which carries the `restrito_por_owner` rule) before touching these.
  def index?
    agent_or_admin?
  end

  def show?
    agent_or_admin?
  end

  def create?
    agent_or_admin?
  end

  def update?
    agent_or_admin?
  end

  def destroy?
    @account_user.administrator?
  end

  private

  def agent_or_admin?
    @account_user.administrator? || @account_user.agent?
  end
end
