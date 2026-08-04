json.payload do
  json.array! @forecast do |row|
    # First day of the month, or null for the deals that still have no expected close date.
    json.period row[:period]
    json.deals_count row[:deals_count]
    json.value_cents row[:value_cents]
    json.weighted_value_cents row[:weighted_value_cents]
  end
end
