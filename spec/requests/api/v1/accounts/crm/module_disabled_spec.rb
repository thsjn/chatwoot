require 'rails_helper'

# The CRM module is opt-in per account (`settings['crm_kanban']`). While it is off the whole API
# surface has to behave as if it had never been deployed, which is what makes "turn the toggle off"
# a real first line of rollback.
RSpec.describe 'CRM module toggle', type: :request do
  let(:account) { create(:account, crm_kanban: false) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:stage) { create(:crm_stage, :entry, account: account, pipeline: pipeline) }
  let(:deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: stage) }
  let(:source) { create(:crm_source, account: account) }
  let(:lost_reason) { create(:crm_lost_reason, account: account) }

  describe 'with the module disabled' do
    it 'answers not found on the pipelines endpoints' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)

      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'answers not found on the stages endpoints' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'answers not found on the deals endpoints' do
      get "/api/v1/accounts/#{account.id}/crm/deals", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)

      patch "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}/move",
            params: { stage_id: stage.id, lock_version: deal.lock_version }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'answers not found on the activities endpoints' do
      get "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}/activities", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'answers not found on the sources endpoints' do
      get "/api/v1/accounts/#{account.id}/crm/sources", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)

      post "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}/regenerate_token", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'answers not found on the lost reasons endpoints' do
      get "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'answers not found on the reports endpoints' do
      %w[funnel stage_durations sales_cycle forecast sources loss_reasons deals_export].each do |metric|
        get "/api/v1/accounts/#{account.id}/crm/reports/#{metric}", params: { pipeline_id: pipeline.id }, headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'does not write through the gate' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm/pipelines", params: { name: 'Comercial' }, headers: headers, as: :json
      end.not_to change(Crm::Pipeline, :count)

      expect(response).to have_http_status(:not_found)

      # The source has to exist before the block: `source` is a lazy `let`, so referencing it inside
      # would create the record there and the counter would move because of the fixture instead of
      # because of the request.
      source_id = source.id

      expect do
        delete "/api/v1/accounts/#{account.id}/crm/sources/#{source_id}", headers: headers, as: :json
      end.not_to change(Crm::Source, :count)

      expect(response).to have_http_status(:not_found)
    end

    # The gate runs before the resource lookups, so an unauthenticated caller still gets the usual
    # 401: the module state is not something an anonymous request may probe.
    it 'still answers unauthorized when there is no session' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'with the module enabled' do
    let(:account) { create(:account, crm_kanban: true) }

    it 'serves the module normally' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines", headers: headers, as: :json

      expect(response).to have_http_status(:success)

      get "/api/v1/accounts/#{account.id}/crm/deals", headers: headers, as: :json

      expect(response).to have_http_status(:success)
    end
  end
end
