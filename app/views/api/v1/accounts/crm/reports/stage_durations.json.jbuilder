json.payload do
  json.array! @stage_durations do |row|
    json.stage_id row[:stage].id
    json.pipeline_id row[:stage].pipeline_id
    json.name row[:stage].name
    json.category row[:stage].category
    json.position row[:stage].position
    # Seconds: the dashboard decides between "3 dias" and "72 h".
    json.avg_duration_seconds row[:avg_duration_seconds]
    json.transitions_count row[:transitions_count]
  end
end
