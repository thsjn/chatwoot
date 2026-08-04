# == Schema Information
#
# Table name: crm_activities
#
#  id           :bigint           not null, primary key
#  completed_at :datetime
#  content      :text
#  due_at       :datetime
#  kind         :integer          default("note"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  deal_id      :bigint           not null
#  user_id      :bigint
#
# Indexes
#
#  index_crm_activities_on_account_id             (account_id)
#  index_crm_activities_on_account_id_and_due_at  (account_id,due_at)
#  index_crm_activities_on_deal_id                (deal_id)
#  index_crm_activities_on_deal_id_and_created_at (deal_id,created_at)
#  index_crm_activities_on_user_id                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (deal_id => crm_deals.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Crm::Activity < ApplicationRecord
  self.table_name = 'crm_activities'

  belongs_to :account
  belongs_to :deal, class_name: 'Crm::Deal', inverse_of: :activities
  belongs_to :user, optional: true

  # `_prefix` keeps `system` and `note` from colliding with Kernel/ActiveRecord methods
  # once Rails generates the enum scopes and predicates.
  enum kind: { note: 0, call: 1, meeting: 2, task: 3, system: 4, whatsapp: 5 }, _prefix: true

  # `account_id` is denormalized here for querying, so it has to be kept in sync with the
  # deal: an activity must never end up logged against another account's deal.
  validate :deal_must_belong_to_account
  validate :user_must_belong_to_account

  scope :pending, -> { where(completed_at: nil).where.not(due_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :overdue, -> { pending.where(due_at: ...Time.current) }
  scope :chronological, -> { order(:created_at, :id) }

  def completed?
    completed_at.present?
  end

  def complete!
    update!(completed_at: Time.current)
  end

  private

  def deal_must_belong_to_account
    return if deal.blank? || deal.account_id == account_id

    errors.add(:deal_id, 'must belong to the same account as the activity')
  end

  def user_must_belong_to_account
    return if user_id.blank? || account.blank? || account.users.exists?(id: user_id)

    errors.add(:user_id, 'must be a member of the same account as the activity')
  end
end
