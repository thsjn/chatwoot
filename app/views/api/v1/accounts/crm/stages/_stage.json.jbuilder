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
# on how many cards the board has paginated in.
json.deals_count aggregates[:deals_count]
json.deals_value_cents aggregates[:deals_value_cents]
