# All the funnel metrics live in a single controller — the same shape as
# `Api::V2::Accounts::ReportsController`: every action shares the exact same input (pipeline +
# date range + policy scoped deals) and differs only in which service it hands it to. Splitting
# them into one controller per metric would duplicate that plumbing six times.
class Api::V1::Accounts::Crm::ReportsController < Api::V1::Accounts::Crm::BaseController
  include DateRangeHelper

  before_action :authorize_report

  def funnel
    @funnel = Crm::Reports::FunnelService.new(**report_scope).perform
  end

  def stage_durations
    @stage_durations = Crm::Reports::StageDurationsService.new(**report_scope).perform
  end

  def sales_cycle
    @sales_cycle = Crm::Reports::SalesCycleService.new(**report_scope).perform
  end

  def forecast
    @forecast = Crm::Reports::ForecastService.new(**report_scope).perform
  end

  def sources
    @sources = Crm::Reports::SourcesService.new(**report_scope).perform
  end

  def loss_reasons
    @loss_reasons = Crm::Reports::LossReasonsService.new(**report_scope).perform
  end

  def deals_export
    @report_data = Crm::Reports::DealsExportService.new(**report_scope, filters: export_filters).perform

    response.headers['Content-Type'] = 'text/csv'
    response.headers['Content-Disposition'] = 'attachment; filename=crm_deals.csv'
    render layout: false, template: 'api/v1/accounts/crm/reports/deals_export', formats: [:csv]
  end

  private

  def authorize_report
    authorize(:report, action_name == 'deals_export' ? :export? : :view?, policy_class: Crm::ReportPolicy)
  end

  # `policy_scope(Crm::Deal)` is what carries the `restrito_por_owner` rule into the aggregates, so
  # no metric ever rebuilds the visibility logic.
  def report_scope
    {
      account: Current.account,
      deals_scope: policy_scope(Crm::Deal),
      pipeline_id: params[:pipeline_id],
      range: range
    }
  end

  def export_filters
    params.permit(:stage_id, :owner_id, :source_id, :status).to_h.symbolize_keys
  end
end
