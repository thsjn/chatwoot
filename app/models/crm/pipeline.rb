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
  # Order matters: Rails runs the `dependent:` callbacks in declaration order, so the restrictive
  # association has to come FIRST. Declared after `stages`, the destroy of a pipeline still holding
  # deals would enqueue the stage destruction job before being refused. Do not reorder.
  has_many :deals, class_name: 'Crm::Deal', dependent: :restrict_with_error, inverse_of: :pipeline
  has_many :stages, class_name: 'Crm::Stage', dependent: :destroy_async, inverse_of: :pipeline

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }

  # Marking a funnel as the default is a SWAP, not a collision: the previous default gives the flag
  # up. Refusing the write instead (which is what a uniqueness validation on `is_default` did) left
  # the only way through as "unset A, then set B", two steps for what the screen offers as one
  # switch.
  #
  # This lives in the model and not in the controller because `is_default` is written from more
  # places than the administration endpoint — seeds, imports and the console all go through `save`,
  # and every one of them has to swap instead of colliding.
  #
  # Order is what makes it safe: `index_crm_pipelines_on_account_id_default` is a partial UNIQUE
  # index and does not forgive two `true` rows even for an instant, so the previous default is
  # cleared BEFORE this row is written. `before_save` runs inside the transaction Rails already
  # opens around the save, so the clear and the write commit together — and a failed write puts the
  # old default back. The index stays as the race guard: two concurrent writers cannot both land.
  before_save :clear_previous_default, if: :becoming_default?

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

  private

  def becoming_default?
    is_default? && will_save_change_to_is_default?
  end

  # `update_all` and not a loop of `update!`: it is a single statement, it takes the row lock a
  # concurrent swap of the same account blocks on, and it must not fire this callback again.
  def clear_previous_default
    # rubocop:disable Rails/SkipsModelValidations
    self.class.where(account_id: account_id, is_default: true)
        .update_all(is_default: false, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
