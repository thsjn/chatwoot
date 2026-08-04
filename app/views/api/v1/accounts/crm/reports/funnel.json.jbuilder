json.payload do
  json.array! @funnel do |row|
    json.stage_id row[:stage].id
    json.pipeline_id row[:stage].pipeline_id
    json.name row[:stage].name
    json.category row[:stage].category
    json.position row[:stage].position
    json.entered_count row[:entered_count]
    json.advanced_count row[:advanced_count]
    json.conversion_rate row[:conversion_rate]
  end
end
