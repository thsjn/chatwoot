json.payload do
  json.array! @loss_reasons do |row|
    # `lost_reason` is null for deals marked as lost without recording a reason.
    if row[:lost_reason].present?
      json.lost_reason do
        json.id row[:lost_reason].id
        json.name row[:lost_reason].name
      end
    else
      json.lost_reason nil
    end

    json.deals_count row[:deals_count]
    json.value_cents row[:value_cents]
  end
end
