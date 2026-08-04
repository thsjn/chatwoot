json.partial! 'api/v1/accounts/crm/stages/stage', formats: [:json], resource: @stage, aggregates: @stage_aggregates[@stage.id],
               filtered_aggregates: @filtered_stage_aggregates&.[](@stage.id)
