json.payload do
  json.array! @lost_reasons do |lost_reason|
    json.partial! 'api/v1/accounts/crm/lost_reasons/lost_reason', formats: [:json], resource: lost_reason
  end
end
