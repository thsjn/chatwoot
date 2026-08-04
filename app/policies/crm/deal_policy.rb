class Crm::DealPolicy < ApplicationPolicy
  def index?
    agent_or_admin?
  end

  def show?
    administrator? || agent_can_access_deal?
  end

  def create?
    agent_or_admin?
  end

  def update?
    administrator? || agent_can_access_deal?
  end

  def destroy?
    administrator?
  end

  # Same rule as `agent_can_access_deal?`, applied in SQL so listings can't leak deals the
  # controller forgot to filter.
  class Scope < Scope
    def resolve
      deals = scope.where(account_id: account.id)
      return deals if account_user.administrator?

      restricted_ids = restricted_pipeline_ids
      return deals if restricted_ids.empty?

      deals.where(
        'crm_deals.pipeline_id NOT IN (:restricted_ids) OR crm_deals.owner_id IS NULL OR crm_deals.owner_id = :user_id',
        restricted_ids: restricted_ids, user_id: user.id
      )
    end

    private

    # `settings ->> 'restrito_por_owner'` renders both a JSON boolean and a "true" string
    # as the text 'true', matching the cast used by the record level check.
    def restricted_pipeline_ids
      Crm::Pipeline.where(account_id: account.id).where("settings ->> 'restrito_por_owner' IN ('true', '1')").pluck(:id)
    end
  end

  private

  def administrator?
    @account_user.administrator?
  end

  def agent_or_admin?
    @account_user.administrator? || @account_user.agent?
  end

  # With `restrito_por_owner` on, an agent only sees their own deals. Ownerless deals stay
  # visible so a lead that arrives without an owner can still be picked up.
  def agent_can_access_deal?
    return false unless @account_user.agent?
    return true unless restricted_by_owner?

    record.owner_id.nil? || record.owner_id == @user.id
  end

  def restricted_by_owner?
    ActiveModel::Type::Boolean.new.cast(record.pipeline.settings['restrito_por_owner'])
  end
end
