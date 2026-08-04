json.payload do
  json.array! @sources do |source|
    json.partial! 'api/v1/accounts/crm/sources/source', formats: [:json], resource: source
  end
end
