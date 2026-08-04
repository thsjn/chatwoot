json.meta do
  # O board pagina por coluna: sem o total, o front nao sabe se ha mais cards
  # a carregar no scroll do estagio.
  json.count @deals_count
  json.current_page @deals.current_page
end

json.payload do
  json.array! @deals do |deal|
    json.partial! 'api/v1/accounts/crm/deals/deal', formats: [:json], resource: deal
  end
end
