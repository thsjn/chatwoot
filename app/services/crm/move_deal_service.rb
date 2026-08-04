class Crm::MoveDealService
  # Business rules that block a move are reported with a stable `error_code` so the board can
  # react (ask for a lost reason, warn about the WIP limit) instead of parsing a message.
  class MoveError < StandardError
    attr_reader :error_code

    def initialize(error_code)
      @error_code = error_code
      super(error_code)
    end
  end

  def initialize(deal:, stage:, user:, position: nil, lock_version: nil, lost_reason_id: nil)
    @deal = deal
    @stage = stage
    @user = user
    @position = position
    @lock_version = lock_version
    @lost_reason_id = lost_reason_id
  end

  def perform
    validate_move!

    from_stage_id = @deal.stage_id
    duration_seconds = duration_in_current_stage
    stage_changed = from_stage_id != @stage.id

    ActiveRecord::Base.transaction do
      apply_attributes(stage_changed)
      @deal.save!
      record_transition(from_stage_id, duration_seconds) if stage_changed
    end

    schedule_rebalance
    @deal
  end

  private

  # The destination column is checked after the drop landed, because the card that just arrived is
  # usually the one that closed the gap. The rewrite itself is a background job: it touches every
  # card of the column and must not sit inside the drag the user is waiting on. Enqueuing is
  # outside the transaction so a rolled back move never schedules one.
  def schedule_rebalance
    return unless Crm::Deal.positions_converging?(@stage.id)

    Crm::RebalanceStagePositionsJob.perform_later(@stage.id)
  end

  # Reordering a card inside its own column is a neutral operation: the lost reason and the WIP
  # limit only guard the transition INTO a stage, so they are skipped when the stage is the same.
  def validate_move!
    raise MoveError, 'lock_version_required' if @lock_version.blank?
    return if @deal.stage_id == @stage.id

    validate_lost_reason! if @stage.category_lost?
    raise MoveError, 'wip_limit_exceeded' if @stage.wip_exceeded?
  end

  # A reason the account turned off is no longer a valid answer for "why did we lose this": it is
  # gone from the picker, so accepting it would keep polluting the loss report with a retired
  # option. The lookup is scoped to the deal's account so an id from another account reads as a
  # missing reason, not as an inactive one.
  def validate_lost_reason!
    reason_id = resolved_lost_reason_id
    raise MoveError, 'lost_reason_required' if reason_id.blank?

    reason = Crm::LostReason.find_by(id: reason_id, account_id: @deal.account_id)
    raise MoveError, 'lost_reason_invalid' if reason.blank?
    raise MoveError, 'lost_reason_inactive' unless reason.active?
  end

  # Assigning `lock_version` from the request makes the UPDATE match on the version the client
  # had, so a card moved by someone else in the meantime raises ActiveRecord::StaleObjectError.
  def apply_attributes(stage_changed)
    @deal.lock_version = @lock_version
    @deal.stage = @stage
    @deal.position = resolved_position
    @deal.stage_entered_at = Time.current if stage_changed
    apply_status
  end

  def apply_status
    if @stage.category_won?
      @deal.status = :won
      @deal.closed_at ||= Time.current
      @deal.lost_reason_id = nil
    elsif @stage.category_lost?
      @deal.status = :lost
      @deal.closed_at ||= Time.current
      @deal.lost_reason_id = resolved_lost_reason_id
    else
      @deal.status = :open
      @deal.closed_at = nil
      @deal.lost_reason_id = nil
    end
  end

  # The board sends the fractional position computed from the drop neighbours. Without it the
  # card goes to the bottom of the destination column. Only active deals count: an archived card
  # is not on the board, so its position must not push new cards further down.
  # The account filter is redundant today (a stage id is unique across the whole table) but keeps
  # the query from being a cross tenant scan by construction.
  def resolved_position
    return @position if @position.present?

    (Crm::Deal.where(account_id: @deal.account_id, stage_id: @stage.id).active.maximum(:position) || 0) + Crm::Deal::POSITION_GAP
  end

  def duration_in_current_stage
    return if @deal.stage_entered_at.blank?

    (Time.current - @deal.stage_entered_at).round
  end

  def resolved_lost_reason_id
    @lost_reason_id.presence || @deal.lost_reason_id
  end

  def record_transition(from_stage_id, duration_seconds)
    Crm::StageTransition.create!(
      deal: @deal, from_stage_id: from_stage_id, to_stage_id: @stage.id,
      user: @user, duration_seconds: duration_seconds
    )
  end
end
