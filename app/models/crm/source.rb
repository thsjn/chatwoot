# == Schema Information
#
# Table name: crm_sources
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  identifier   :string
#  kind         :integer          default("inbox"), not null
#  name         :string           not null
#  token_digest :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  inbox_id     :bigint
#
# Indexes
#
#  index_crm_sources_on_account_id                 (account_id)
#  index_crm_sources_on_account_id_and_identifier  (account_id,identifier)
#  index_crm_sources_on_account_id_and_kind        (account_id,kind)
#  index_crm_sources_on_inbox_id                   (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#
class Crm::Source < ApplicationRecord
  self.table_name = 'crm_sources'

  belongs_to :account
  belongs_to :inbox, optional: true
  has_many :deals, class_name: 'Crm::Deal', foreign_key: :source_id, dependent: :nullify, inverse_of: :source

  # `_prefix` is mandatory here: the `inbox` value would otherwise clash with the
  # `belongs_to :inbox` association and `api`/`import` read poorly without it.
  enum kind: { inbox: 0, landing: 1, import: 2, api: 3, n8n: 4, manual: 5 }, _prefix: true

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :identifier, uniqueness: { scope: :account_id }, allow_blank: true

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
end
