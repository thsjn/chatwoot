# == Schema Information
#
# Table name: crm_stages
#
#  id           :bigint           not null, primary key
#  category     :integer          default("open"), not null
#  color        :string
#  is_entry     :boolean          default(FALSE), not null
#  name         :string           not null
#  position     :integer          default(0), not null
#  probability  :integer          default(0), not null
#  rotting_days :integer
#  wip_limit    :integer
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  pipeline_id  :bigint           not null
#
# Indexes
#
#  index_crm_stages_on_account_id               (account_id)
#  index_crm_stages_on_account_id_and_category  (account_id,category)
#  index_crm_stages_on_pipeline_id              (pipeline_id)
#  index_crm_stages_on_pipeline_id_and_position (pipeline_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (pipeline_id => crm_pipelines.id) ON DELETE => cascade
#
class Crm::Stage < ApplicationRecord
  self.table_name = 'crm_stages'

  # `color` is a design token, never a hex value: the dashboard styles the column with Tailwind
  # utility classes and cannot apply an arbitrary colour coming from the database.
  COLORS = %w[slate blue emerald amber ruby violet].freeze

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline', inverse_of: :stages
  has_many :deals, class_name: 'Crm::Deal', dependent: :restrict_with_error, inverse_of: :stage

  # `_prefix` avoids shadowing the Deal-ish `open`/`won`/`lost` scopes and keeps
  # `Crm::Stage.category_open` explicit at the call site.
  enum category: { open: 0, won: 1, lost: 2 }, _prefix: true

  validates :name, presence: true
  validates :name, uniqueness: { scope: :pipeline_id }
  validates :color, inclusion: { in: COLORS }, allow_nil: true
  validates :probability, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :rotting_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :wip_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # The pipeline FK only guarantees the row exists, so without this a stage could be
  # attached to another account's pipeline.
  validate :pipeline_must_belong_to_account

  scope :ordered, -> { order(:position, :id) }
  scope :entry, -> { where(is_entry: true) }

  def closing?
    category_won? || category_lost?
  end

  def wip_exceeded?
    return false if wip_limit.blank?

    deals.active.where(status: :open).count >= wip_limit
  end

  private

  def pipeline_must_belong_to_account
    return if pipeline.blank? || pipeline.account_id == account_id

    errors.add(:pipeline_id, 'must belong to the same account as the stage')
  end
end
