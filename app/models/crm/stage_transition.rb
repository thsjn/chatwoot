# == Schema Information
#
# Table name: crm_stage_transitions
#
#  id               :bigint           not null, primary key
#  automated        :boolean          default(FALSE), not null
#  duration_seconds :integer
#  created_at       :datetime         not null
#  deal_id          :bigint           not null
#  from_stage_id    :bigint
#  to_stage_id      :bigint           not null
#  user_id          :bigint
#
# Indexes
#
#  index_crm_stage_transitions_on_deal_id                 (deal_id)
#  index_crm_stage_transitions_on_deal_id_and_created_at  (deal_id,created_at)
#  index_crm_stage_transitions_on_from_stage_id           (from_stage_id)
#  index_crm_stage_transitions_on_to_stage_id             (to_stage_id)
#  index_crm_stage_transitions_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (deal_id => crm_deals.id) ON DELETE => cascade
#  fk_rails_...  (from_stage_id => crm_stages.id) ON DELETE => nullify
#  fk_rails_...  (to_stage_id => crm_stages.id)
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Crm::StageTransition < ApplicationRecord
  self.table_name = 'crm_stage_transitions'

  # Append only audit trail: the table carries created_at but no updated_at,
  # which Rails handles transparently.
  belongs_to :deal, class_name: 'Crm::Deal', inverse_of: :stage_transitions
  belongs_to :from_stage, class_name: 'Crm::Stage', optional: true
  belongs_to :to_stage, class_name: 'Crm::Stage'
  belongs_to :user, optional: true

  # This table has no `account_id` of its own, so the account check has to compare every
  # reference against the deal: an audit entry must never point at another account's stage
  # or credit the move to a user outside the account.
  validate :from_stage_must_belong_to_deal_account
  validate :to_stage_must_belong_to_deal_account
  validate :user_must_belong_to_deal_account

  scope :automated, -> { where(automated: true) }
  scope :manual, -> { where(automated: false) }
  scope :chronological, -> { order(:created_at, :id) }

  private

  def from_stage_must_belong_to_deal_account
    return if deal.blank? || from_stage.blank? || from_stage.account_id == deal.account_id

    errors.add(:from_stage_id, 'must belong to the same account as the deal')
  end

  def to_stage_must_belong_to_deal_account
    return if deal.blank? || to_stage.blank? || to_stage.account_id == deal.account_id

    errors.add(:to_stage_id, 'must belong to the same account as the deal')
  end

  def user_must_belong_to_deal_account
    return if deal.blank? || user_id.blank? || deal.account.users.exists?(id: user_id)

    errors.add(:user_id, 'must be a member of the same account as the deal')
  end
end
