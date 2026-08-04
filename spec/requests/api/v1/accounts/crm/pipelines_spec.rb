require 'rails_helper'

RSpec.describe 'CRM Pipelines API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }
  let!(:pipeline) { create(:crm_pipeline, account: account, name: 'Comercial', position: 0) }

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user belongs to another account' do
      it 'does not expose this account resources' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines",
            headers: foreign_admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      let!(:other_account_pipeline) { create(:crm_pipeline, account: other_account) }

      it 'lists only the pipelines of the current account' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to eq([pipeline.id])
        expect(ids).not_to include(other_account_pipeline.id)
      end

      it 'orders the pipelines by position' do
        first = create(:crm_pipeline, account: account, position: -1)

        get "/api/v1/accounts/#{account.id}/crm/pipelines",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([first.id, pipeline.id])
      end

      it 'is readable by an agent' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the pipeline with its settings' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(pipeline.id)
        expect(response.parsed_body['name']).to eq('Comercial')
        expect(response.parsed_body['settings']['moeda_padrao']).to eq('BRL')
      end

      it 'returns not found for a pipeline of another account' do
        foreign_pipeline = create(:crm_pipeline, account: other_account)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{foreign_pipeline.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines' do
    let(:valid_params) do
      {
        pipeline: {
          name: 'Inbound',
          description: 'Leads que chegam pelo site',
          position: 2,
          settings: { restrito_por_owner: true, moeda_padrao: 'BRL', inbox_ids: [] }
        }
      }
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines", params: valid_params, as: :json
        end.not_to change(Crm::Pipeline, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to create pipelines' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines",
               params: valid_params, headers: agent.create_new_auth_token, as: :json
        end.not_to change(Crm::Pipeline, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an administrator' do
      it 'creates the pipeline' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines",
               params: valid_params, headers: admin.create_new_auth_token, as: :json
        end.to change(Crm::Pipeline, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['name']).to eq('Inbound')
        expect(response.parsed_body['settings']['restrito_por_owner']).to be(true)
        expect(Crm::Pipeline.find(response.parsed_body['id']).account_id).to eq(account.id)
      end

      it 'returns unprocessable entity when the name is missing' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines",
             params: { pipeline: { name: '' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/pipelines/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
              params: { pipeline: { name: 'Novo' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to update pipelines' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
              params: { pipeline: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(pipeline.reload.name).to eq('Comercial')
      end
    end

    context 'when the user is an administrator' do
      it 'updates the pipeline' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
              params: { pipeline: { name: 'Comercial 2026', position: 9 } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(pipeline.reload.name).to eq('Comercial 2026')
        expect(pipeline.position).to eq(9)
      end

      # Turning the "default funnel" switch on used to answer 422 because another pipeline already
      # held the flag, leaving the administrator to unset the old one first. It is a swap now.
      it 'moves the default flag away from the pipeline that held it' do
        previous_default = create(:crm_pipeline, :default, account: account)

        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
              params: { pipeline: { is_default: true } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['is_default']).to be(true)
        expect(pipeline.reload.is_default).to be(true)
        expect(previous_default.reload.is_default).to be(false)
        expect(Crm::Pipeline.where(account_id: account.id, is_default: true).count).to eq(1)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/pipelines/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}"

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Pipeline.exists?(pipeline.id)).to be(true)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to delete pipelines' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Pipeline.exists?(pipeline.id)).to be(true)
      end
    end

    context 'when the user is an administrator' do
      it 'deletes a pipeline without deals' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
               headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(Crm::Pipeline.exists?(pipeline.id)).to be(false)
      end

      it 'returns unprocessable entity when the pipeline still has deals' do
        create(:crm_deal, account: account, pipeline: pipeline)

        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
               headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
        expect(Crm::Pipeline.exists?(pipeline.id)).to be(true)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines/:id/archive' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/archive"

        expect(response).to have_http_status(:unauthorized)
        expect(pipeline.reload.archived_at).to be_nil
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to retire a pipeline' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/archive",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(pipeline.reload.archived_at).to be_nil
      end
    end

    context 'when the user is an administrator' do
      it 'archives the pipeline' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/archive",
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['archived_at']).to be_present
        expect(pipeline.reload.archived_at).to be_present
      end

      # This is the whole point of archiving instead of deleting: `destroy` is refused while the
      # pipeline holds deals, so archiving has to retire it WITHOUT touching the cards.
      it 'keeps every deal of the pipeline intact' do
        deal = create(:crm_deal, account: account, pipeline: pipeline)

        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/archive",
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(deal.reload.archived_at).to be_nil
        expect(deal.pipeline_id).to eq(pipeline.id)
        expect(deal.status).to eq('open')
      end

      it 'returns not found for a pipeline of another account' do
        foreign_pipeline = create(:crm_pipeline, account: other_account)

        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{foreign_pipeline.id}/archive",
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(foreign_pipeline.reload.archived_at).to be_nil
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines/:id/unarchive' do
    let!(:pipeline) { create(:crm_pipeline, :archived, account: account, name: 'Comercial antigo') }

    context 'when the user is an agent' do
      it 'is not allowed to restore a pipeline' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/unarchive",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(pipeline.reload.archived_at).to be_present
      end
    end

    context 'when the user is an administrator' do
      it 'restores the pipeline' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/unarchive",
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['archived_at']).to be_nil
        expect(pipeline.reload.archived_at).to be_nil
      end
    end
  end

  describe 'archived pipelines on the listing' do
    let!(:archived_pipeline) { create(:crm_pipeline, :archived, account: account, name: 'Comercial 2024', position: 1) }

    # The board reads this listing to fill its pipeline selector, so a retired funnel must not be
    # in it — otherwise it stays on screen forever.
    it 'hides the archived pipelines by default' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines",
          headers: agent.create_new_auth_token, as: :json

      ids = response.parsed_body['payload'].pluck('id')
      expect(ids).to include(pipeline.id)
      expect(ids).not_to include(archived_pipeline.id)
    end

    it 'lists the archived pipelines when the administration asks for them' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines",
          params: { include_archived: true }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to include(archived_pipeline.id)
    end

    it 'keeps the archived pipeline reachable on its own so it can be restored' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{archived_pipeline.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['archived_at']).to be_present
    end
  end
end
