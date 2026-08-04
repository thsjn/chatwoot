class Crm::SourcePolicy < ApplicationPolicy
  # Sources carry ingestion credentials (token_digest), so only administrators manage them.
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

  # Minting the token is handing out a credential that writes into the funnel from outside the
  # product, so it never reaches an agent.
  def regenerate_token?
    @account_user.administrator?
  end
end
