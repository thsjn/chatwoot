# Funnel metrics are a working tool, not an admin-only dashboard: an agent has to see where their
# own deals stall as much as a manager does, so reading is open to both roles — unlike
# `ReportPolicy` (conversations), which is administrator only.
#
# The interesting case is the agent on a pipeline with `restrito_por_owner`. Widening the metrics
# to the whole funnel for them would defeat the restriction: totals, averages and forecasts are
# enough to reconstruct what the setting is meant to hide (how much the other agents are carrying,
# what they are closing, which channels they are working). So the metrics reuse
# `Crm::DealPolicy::Scope` untouched — a restricted agent gets the SAME numbers as their board:
# their own deals plus the ownerless ones. Nothing new to keep in sync, and the aggregate can never
# reveal what the listing already hides.
class Crm::ReportPolicy < ApplicationPolicy
  def view?
    @account_user.administrator? || @account_user.agent?
  end

  # The export carries deal-level rows (contact, owner, value), so it follows exactly the same rule
  # and the same policy scope as the board listing.
  def export?
    view?
  end
end
