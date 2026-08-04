# The board sends the same filters to the deals index and to the stages index: the cards come from
# the first, the column headers from the second, and the two only agree if they read the filters
# the same way. Keeping the translation in one place is what makes the filtered aggregate of a
# column match the cards actually listed under it.
module Crm::DealFilterable
  extend ActiveSupport::Concern

  private

  def apply_deal_filters(scope)
    scope = scope.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    scope = scope.where(stage_id: params[:stage_id]) if params[:stage_id].present?
    scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    scope = scope.where(source_id: params[:source_id]) if params[:source_id].present?
    scope = scope.where(status: params[:status]) if filtering_by_status?
    scope = scope.where('crm_deals.title ILIKE :search', search: "%#{params[:q].strip}%") if params[:q].present?
    apply_expected_close_filter(scope)
  end

  # `since`/`until` mirrors the naming the reports already use (DateRangeHelper), which is what the
  # board sends. Deals without `expected_close_on` fall out of a bounded range on purpose: a filter
  # by closing period is a question about dated deals.
  def apply_expected_close_filter(scope)
    scope = scope.where(expected_close_on: Date.parse(params[:expected_close_since])..) if params[:expected_close_since].present?
    scope = scope.where(expected_close_on: ..Date.parse(params[:expected_close_until])) if params[:expected_close_until].present?
    scope
  rescue Date::Error
    scope
  end

  def filtering_by_status?
    Crm::Deal.statuses.key?(params[:status])
  end
end
