json.payload do
  json.array! @sources do |row|
    # `source` is null for deals closed without a channel tagged.
    if row[:source].present?
      json.source do
        json.id row[:source].id
        json.name row[:source].name
        json.kind row[:source].kind
      end
    else
      json.source nil
    end

    json.won_count row[:won_count]
    json.won_value_cents row[:won_value_cents]
    json.lost_count row[:lost_count]
    json.lost_value_cents row[:lost_value_cents]
    json.win_rate row[:win_rate]
  end
end
