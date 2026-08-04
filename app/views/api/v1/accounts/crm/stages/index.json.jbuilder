json.payload do
  json.array! @stages do |stage|
    json.partial! 'api/v1/accounts/crm/stages/stage', formats: [:json], resource: stage
  end
end
