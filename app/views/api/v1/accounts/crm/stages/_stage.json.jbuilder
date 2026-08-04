json.id resource.id
json.pipeline_id resource.pipeline_id
json.name resource.name
json.position resource.position
json.color resource.color
json.category resource.category
json.probability resource.probability
json.rotting_days resource.rotting_days
json.wip_limit resource.wip_limit
json.is_entry resource.is_entry

# Totals of the whole stage (open, non archived deals), so the column header does not depend
# on how many cards the board has paginated in. This is also the number the WIP limit is measured
# against: the limit is a property of the column, not of what the current filter reveals.
json.deals_count aggregates[:deals_count]
json.deals_value_cents aggregates[:deals_value_cents]

# Same totals restricted to the board filters, so a filtered column can show how many of its
# cards matched without losing sight of how full it really is.
json.filtered_deals_count filtered_aggregates[:deals_count]
json.filtered_deals_value_cents filtered_aggregates[:deals_value_cents]
