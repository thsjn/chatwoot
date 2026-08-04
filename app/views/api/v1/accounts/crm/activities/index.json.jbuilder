json.meta do
  # A timeline grows without bound, so the drawer loads it page by page and needs the total
  # to know whether there is more history behind the current page.
  json.count @activities_count
  json.current_page @activities.current_page
end

json.payload do
  json.array! @activities do |activity|
    json.partial! 'api/v1/accounts/crm/activities/activity', formats: [:json], resource: activity
  end
end
