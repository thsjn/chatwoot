# == Schema Information
#
# Table name: crm_deals
#
#  id                :bigint           not null, primary key
#  archived_at       :datetime
#  closed_at         :datetime
#  currency          :string           default("BRL"), not null
#  custom_attributes :jsonb            not null
#  expected_close_on :date
#  last_activity_at  :datetime
#  lock_version      :integer          default(0), not null
#  position          :decimal(, )      default(0.0), not null
#  stage_entered_at  :datetime
#  status            :integer          default("open"), not null
#  title             :string           not null
#  utm               :jsonb            not null
#  value_cents       :bigint           default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  contact_id        :bigint           not null
#  lost_reason_id    :bigint
#  owner_id          :bigint
#  pipeline_id       :bigint           not null
#  source_id         :bigint
#  source_inbox_id   :bigint
#  stage_id          :bigint           not null
#  team_id           :bigint
#
# Indexes
#
#  index_crm_deals_active_on_account_pipeline_close_on  (account_id,pipeline_id,expected_close_on) WHERE (archived_at IS NULL)
#  index_crm_deals_active_on_account_pipeline_closed     (account_id,pipeline_id,closed_at) WHERE (archived_at IS NULL)
#  index_crm_deals_active_on_account_pipeline_created    (account_id,pipeline_id,created_at) WHERE (archived_at IS NULL)
#  index_crm_deals_active_on_pipeline_status_stage       (pipeline_id,status,stage_id) WHERE (archived_at IS NULL)
#  index_crm_deals_active_on_stage_position              (stage_id,position,id) WHERE (archived_at IS NULL)
#  index_crm_deals_on_account_id                  (account_id)
#  index_crm_deals_on_account_id_and_archived_at  (account_id,archived_at)
#  index_crm_deals_on_account_id_and_status       (account_id,status)
#  index_crm_deals_on_account_pipeline_stage      (account_id,pipeline_id,stage_id)
#  index_crm_deals_on_contact_id                  (contact_id)
#  index_crm_deals_on_lost_reason_id              (lost_reason_id)
#  index_crm_deals_on_owner_id                    (owner_id)
#  index_crm_deals_on_pipeline_id                 (pipeline_id)
#  index_crm_deals_on_source_id                   (source_id)
#  index_crm_deals_on_source_inbox_id             (source_inbox_id)
#  index_crm_deals_on_stage_id                    (stage_id)
#  index_crm_deals_on_stage_id_and_position       (stage_id,position)
#  index_crm_deals_on_team_id                     (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (lost_reason_id => crm_lost_reasons.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#  fk_rails_...  (source_id => crm_sources.id) ON DELETE => nullify
#  fk_rails_...  (source_inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (stage_id => crm_stages.id)
#  fk_rails_...  (team_id => teams.id) ON DELETE => nullify
#
class Crm::Deal < ApplicationRecord
  include Crm::DealBroadcastable

  self.table_name = 'crm_deals'

  # `position` is a numeric (not an integer) on purpose: the board uses fractional indexing.
  # Dropping a card between two neighbours writes the average of their positions
  # (e.g. between 1.0 and 2.0 -> 1.5), so reordering touches a single row instead of
  # renumbering the whole column. Dropping at the top/bottom uses `min - POSITION_GAP` /
  # `max + POSITION_GAP`. When neighbours get too close, `Crm::MoveDealService` hands the column
  # to `Crm::RebalanceStagePositionsJob`, which renumbers it as multiples of POSITION_GAP.
  POSITION_GAP = 1000

  # Every drop into the same interval halves the remaining room (1000 -> 500 -> 250 ...), so after
  # roughly fifty successive drops the neighbours are less than one unit apart and the next midpoint
  # stops being representable as a distinct value: two cards collide and the column order becomes
  # arbitrary. One whole unit of slack is the point where the column is renumbered in background.
  POSITION_REBALANCE_THRESHOLD = 1

  # Smallest distance between two neighbouring cards of a column, which is what tells the move
  # service the fractional indexing has run out of room. It is a single window pass over
  # `index_crm_deals_active_on_stage_position`, so it costs one indexed query per move.
  MIN_POSITION_GAP_SQL = <<~SQL.squish.freeze
    SELECT MIN(gap) FROM (
      SELECT position - LAG(position) OVER (ORDER BY position, id) AS gap
        FROM crm_deals
       WHERE stage_id = :stage_id AND archived_at IS NULL
    ) gaps
  SQL

  # The board card shows whether the deal has a next step scheduled, and a listing renders 25
  # cards per column: resolving that per record would be one query per card. This correlated
  # subquery rides along the listing query as an extra column (see the `with_next_activity`
  # scope) and is covered by `index_crm_activities_pending_on_deal_id_and_due_at`.
  # `now() AT TIME ZONE 'UTC'` matches the `timestamp without time zone` columns Rails writes
  # in UTC, so the comparison does not depend on the Postgres session timezone.
  NEXT_ACTIVITY_AT_SQL = <<~SQL.squish.freeze
    (SELECT MIN(crm_activities.due_at)
       FROM crm_activities
      WHERE crm_activities.deal_id = crm_deals.id
        AND crm_activities.completed_at IS NULL
        AND crm_activities.due_at > (now() AT TIME ZONE 'UTC')) AS next_activity_at
  SQL

  # `lock_version` enables Rails optimistic locking out of the box (the column name must
  # be exactly this). Two agents dragging the same card concurrently make the second save
  # raise ActiveRecord::StaleObjectError instead of silently overwriting the first.

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline', inverse_of: :deals
  belongs_to :stage, class_name: 'Crm::Stage', inverse_of: :deals
  belongs_to :contact
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :team, optional: true
  belongs_to :source, class_name: 'Crm::Source', optional: true, inverse_of: :deals
  belongs_to :source_inbox, class_name: 'Inbox', optional: true
  belongs_to :lost_reason, class_name: 'Crm::LostReason', optional: true, inverse_of: :deals

  has_many :deal_conversations, class_name: 'Crm::DealConversation', foreign_key: :deal_id, dependent: :destroy,
                                inverse_of: :deal
  has_many :conversations, through: :deal_conversations, source: :conversation
  has_many :stage_transitions, class_name: 'Crm::StageTransition', foreign_key: :deal_id, dependent: :delete_all,
                               inverse_of: :deal
  has_many :activities, class_name: 'Crm::Activity', foreign_key: :deal_id, dependent: :destroy, inverse_of: :deal

  enum status: { open: 0, won: 1, lost: 2 }

  # Creation is the first step of the funnel, so it is recorded as a transition with no origin
  # stage (see `record_creation_transition`). These accessors carry the little context the
  # audit entry needs and that the record itself cannot know: who created the card and whether
  # it came from the conversation ingestion instead of a human action.
  attr_accessor :creation_user, :creation_automated

  validates :title, presence: true
  validates :currency, presence: true
  validates :value_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :custom_attributes, jsonb_attributes_length: true

  # The foreign keys only guarantee the referenced row exists, not that it belongs to this
  # account/pipeline. Without these checks a crafted payload could point a deal at another
  # account's pipeline, contact or source, breaking tenant isolation.
  validate :stage_must_belong_to_pipeline
  validate :pipeline_must_belong_to_account
  validate :contact_must_belong_to_account
  validate :owner_must_belong_to_account
  validate :team_must_belong_to_account
  validate :source_must_belong_to_account
  validate :source_inbox_must_belong_to_account
  validate :lost_reason_must_belong_to_account
  validate :lost_reason_must_be_active
  validate :custom_attributes_must_be_defined

  before_create :ensure_stage_entered_at
  after_create :record_creation_transition

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  scope :in_stage, ->(stage_id) { where(stage_id: stage_id).ordered }
  scope :with_next_activity, -> { select('crm_deals.*', Arel.sql(NEXT_ACTIVITY_AT_SQL)) }
  scope :rotting, lambda {
    open.active
        .joins(:stage)
        .where.not(crm_stages: { rotting_days: nil })
        .where("crm_deals.stage_entered_at < now() - (crm_stages.rotting_days * interval '1 day')")
  }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def value
    value_cents.to_i / 100.0
  end

  def origin_conversation
    deal_conversations.find_by(is_origin: true)&.conversation
  end

  # Earliest due date still ahead of us among the activities nobody completed yet, which is
  # what the "every open deal needs a next step" rule is checked against. Listings load it
  # through `with_next_activity`; a single record (show/create/update) resolves it here.
  def next_activity_at
    return self[:next_activity_at] if has_attribute?(:next_activity_at)

    activities.pending.where(due_at: Time.current..).minimum(:due_at)
  end

  # True when the column no longer has room to split between two cards, which is the signal to
  # renumber it. A column with a single card (or none) has no gap to measure and reads as fine.
  def self.positions_converging?(stage_id)
    gap = connection.select_value(sanitize_sql_array([MIN_POSITION_GAP_SQL, { stage_id: stage_id }]))

    gap.present? && gap.to_d < POSITION_REBALANCE_THRESHOLD
  end

  private

  def ensure_stage_entered_at
    self.stage_entered_at ||= Time.current
  end

  # The entry into the first stage is a real step of the funnel and has to be auditable like any
  # other move, otherwise the report has to guess where the card came into the pipeline. It is
  # written here (and not in the callers) so every path that creates a deal — the API, the
  # conversation ingestion, a seed — produces the same history.
  # `from_stage_id` is NULL because there is no origin stage, and `duration_seconds` is NULL
  # because no time was spent anywhere before this.
  def record_creation_transition
    Crm::StageTransition.create!(
      deal: self, from_stage_id: nil, to_stage_id: stage_id,
      user: creation_user, duration_seconds: nil,
      automated: ActiveModel::Type::Boolean.new.cast(creation_automated).present?
    )
  end

  # `pipeline`, `stage` and `contact` are already loaded by the `belongs_to` presence
  # validations, and the optional ones only hit the database when their id is present,
  # so these checks add no query on the common path.
  def stage_must_belong_to_pipeline
    return if stage.blank? || pipeline_id.blank? || stage.pipeline_id == pipeline_id

    errors.add(:stage_id, 'must belong to the pipeline of the deal')
  end

  def pipeline_must_belong_to_account
    return if pipeline.blank? || pipeline.account_id == account_id

    errors.add(:pipeline_id, 'must belong to the same account as the deal')
  end

  def contact_must_belong_to_account
    return if contact.blank? || contact.account_id == account_id

    errors.add(:contact_id, 'must belong to the same account as the deal')
  end

  def owner_must_belong_to_account
    return if owner_id.blank? || account.blank? || account.users.exists?(id: owner_id)

    errors.add(:owner_id, 'must be a member of the same account as the deal')
  end

  def team_must_belong_to_account
    return if team.blank? || team.account_id == account_id

    errors.add(:team_id, 'must belong to the same account as the deal')
  end

  def source_must_belong_to_account
    return if source.blank? || source.account_id == account_id

    errors.add(:source_id, 'must belong to the same account as the deal')
  end

  def source_inbox_must_belong_to_account
    return if source_inbox.blank? || source_inbox.account_id == account_id

    errors.add(:source_inbox_id, 'must belong to the same account as the deal')
  end

  def lost_reason_must_belong_to_account
    return if lost_reason.blank? || lost_reason.account_id == account_id

    errors.add(:lost_reason_id, 'must belong to the same account as the deal')
  end

  # A reason turned off must not be picked again, but deactivating one cannot make the deals that
  # already carry it unsaveable, so the check only runs when the reason is being assigned.
  def lost_reason_must_be_active
    return if lost_reason.blank? || !lost_reason_id_changed? || lost_reason.active?

    errors.add(:lost_reason_id, 'must be an active lost reason')
  end

  # Custom fields are the account's `custom_attribute_definitions` scoped to `deal_attribute`, the
  # same registry the rest of Chatwoot uses for contacts and conversations. Anything outside it is
  # a typo or a stale client, and letting it through would silently create a field nobody can read
  # back on the UI. A `list` definition goes one step further and is a closed set of options, so a
  # value outside it would render as an empty select.
  def custom_attributes_must_be_defined
    return unless custom_attributes_changed?
    return if custom_attributes.blank? || account_id.blank?

    definitions = CustomAttributeDefinition.where(account_id: account_id).deal_attribute.index_by(&:attribute_key)

    custom_attributes.each do |key, value|
      definition = definitions[key.to_s]

      if definition.nil?
        errors.add(:custom_attributes, "#{key} is not a custom attribute defined for deals")
      elsif definition.list? && value.present? && definition.attribute_values.to_a.map(&:to_s).exclude?(value.to_s)
        errors.add(:custom_attributes, "#{key} must be one of the values defined for it")
      end
    end
  end
end
