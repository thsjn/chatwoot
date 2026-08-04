json.partial! 'api/v1/accounts/crm/sources/source', formats: [:json], resource: @source
json.token @plain_token
json.ingestion_url public_api_v1_account_crm_leads_url(account_id: Current.account.id)
