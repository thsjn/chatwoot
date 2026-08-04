json.payload do
  json.array! @activities do |activity|
    json.partial! 'api/v1/accounts/crm/activities/activity', formats: [:json], resource: activity
  end
end
