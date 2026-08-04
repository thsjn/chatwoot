# == Schema Information
#
# Table name: crm_deal_conversations
#
#  id              :bigint           not null, primary key
#  is_origin       :boolean          default(FALSE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conversation_id :bigint           not null
#  deal_id         :bigint           not null
#
# Indexes
#
#  index_crm_deal_conversations_on_conversation_id       (conversation_id)
#  index_crm_deal_conversations_on_deal_and_conversation (deal_id,conversation_id) UNIQUE
#  index_crm_deal_conversations_on_deal_id               (deal_id)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (deal_id => crm_deals.id) ON DELETE => cascade
#
class Crm::DealConversation < ApplicationRecord
  self.table_name = 'crm_deal_conversations'

  belongs_to :deal, class_name: 'Crm::Deal', inverse_of: :deal_conversations
  belongs_to :conversation

  validates :conversation_id, uniqueness: { scope: :deal_id }

  # This join table has no `account_id` of its own, so the account check has to compare the
  # conversation against the deal: linking a conversation from another account would expose
  # its messages through the deal.
  validate :conversation_must_belong_to_deal_account

  scope :origin, -> { where(is_origin: true) }

  private

  def conversation_must_belong_to_deal_account
    return if deal.blank? || conversation.blank? || conversation.account_id == deal.account_id

    errors.add(:conversation_id, 'must belong to the same account as the deal')
  end
end
