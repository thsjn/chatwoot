# == Schema Information
#
# Table name: crm_pipelines
#
#  id          :bigint           not null, primary key
#  archived_at :datetime
#  description :text
#  is_default  :boolean          default(FALSE), not null
#  name        :string           not null
#  position    :integer          default(0), not null
#  settings    :jsonb            not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_crm_pipelines_on_account_id                  (account_id)
#  index_crm_pipelines_on_account_id_and_archived_at  (account_id,archived_at)
#  index_crm_pipelines_on_account_id_and_position     (account_id,position)
#  index_crm_pipelines_on_account_id_default          (account_id) UNIQUE WHERE (is_default = true)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::Pipeline < ApplicationRecord
  self.table_name = 'crm_pipelines'

  # Keys expected inside `settings`:
  #   inbox_ids                 -> inboxes used for lead ingestion
  #   janela_dedupe_dias        -> dedupe window (in days) when creating deals from conversations
  #   exige_proxima_atividade   -> forces the deal to always have a next activity scheduled
  #   moeda_padrao              -> default currency for new deals
  #   restrito_por_owner        -> restricts board visibility to the deal owner
  SETTINGS_KEYS = %w[inbox_ids janela_dedupe_dias exige_proxima_atividade moeda_padrao restrito_por_owner].freeze

  belongs_to :account
  has_many :stages, class_name: 'Crm::Stage', dependent: :destroy_async, inverse_of: :pipeline
  has_many :deals, class_name: 'Crm::Deal', dependent: :restrict_with_error, inverse_of: :pipeline

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :is_default, uniqueness: { scope: :account_id, conditions: -> { where(is_default: true) } }, if: :is_default?

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def entry_stage
    stages.find_by(is_entry: true) || stages.ordered.first
  end
end
