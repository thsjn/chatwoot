# Rows of the deals CSV export. The service only produces the data; the CSV itself is rendered by
# the `.csv.erb` template through `CSVSafe`, which is what neutralises formula injection in the
# text columns (a deal titled `=cmd|...` would otherwise execute when the file is opened).
#
# This is the one report that legitimately loads records instead of aggregating: the export IS the
# rows. `find_each` keeps memory flat and gives a deterministic order (id asc).
class Crm::Reports::DealsExportService < Crm::Reports::BaseService
  def initialize(account:, deals_scope: Crm::Deal, pipeline_id: nil, range: nil, filters: {})
    super(account: account, deals_scope: deals_scope, pipeline_id: pipeline_id, range: range)
    @filters = filters
  end

  def perform
    rows = []
    export_deals.find_each(batch_size: 500) { |deal| rows << row_for(deal) }
    rows
  end

  private

  def export_deals
    scope = deals_between(:created_at).includes(:stage, :contact, :owner, :source, :lost_reason)
    scope = scope.where(stage_id: @filters[:stage_id]) if @filters[:stage_id].present?
    scope = scope.where(owner_id: @filters[:owner_id]) if @filters[:owner_id].present?
    scope = scope.where(source_id: @filters[:source_id]) if @filters[:source_id].present?
    scope = scope.where(status: @filters[:status]) if Crm::Deal.statuses.key?(@filters[:status])
    scope
  end

  def row_for(deal)
    [
      deal.title,
      format('%.2f', deal.value),
      deal.currency,
      deal.stage.name,
      deal.status,
      deal.contact.name,
      deal.owner&.available_name,
      deal.source&.name,
      deal.lost_reason&.name,
      deal.created_at.iso8601,
      deal.closed_at&.iso8601
    ]
  end
end
