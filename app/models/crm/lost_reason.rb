# == Schema Information
#
# Table name: crm_lost_reasons
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_crm_lost_reasons_on_account_id               (account_id)
#  index_crm_lost_reasons_on_account_id_and_position  (account_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::LostReason < ApplicationRecord
  self.table_name = 'crm_lost_reasons'

  belongs_to :account
  has_many :deals, class_name: 'Crm::Deal', foreign_key: :lost_reason_id, dependent: :nullify, inverse_of: :lost_reason

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :ordered, -> { order(:position, :id) }
end
