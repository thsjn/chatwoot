require 'rails_helper'

RSpec.describe 'CRM Stages API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let!(:stage) { create(:crm_stage, account: account, pipeline: pipeline, name: 'Qualificacao', position: 1) }

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user belongs to another account' do
      it 'does not expose this account resources' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: foreign_admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'lists the stages of the pipeline ordered by position' do
        entry = create(:crm_stage, :entry, account: account, pipeline: pipeline, position: 0)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].pluck('id')).to eq([entry.id, stage.id])
      end

      it 'is readable by an agent' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      it 'returns not found for a pipeline of another account' do
        foreign_pipeline = create(:crm_pipeline, account: other_account)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{foreign_pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the stage' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(stage.id)
        expect(response.parsed_body['name']).to eq('Qualificacao')
      end

      it 'returns not found for a stage of another pipeline' do
        other_pipeline = create(:crm_pipeline, account: account)
        other_stage = create(:crm_stage, account: account, pipeline: other_pipeline)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{other_stage.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages' do
    let(:valid_params) do
      { stage: { name: 'Proposta', category: 'open', position: 3, color: '#ff0000', probability: 60, wip_limit: 5, rotting_days: 7 } }
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages", params: valid_params, as: :json
        end.not_to change(Crm::Stage, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to create stages' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
               params: valid_params, headers: agent.create_new_auth_token, as: :json
        end.not_to change(Crm::Stage, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an administrator' do
      it 'creates the stage inside the pipeline and the current account' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
               params: valid_params, headers: admin.create_new_auth_token, as: :json
        end.to change(Crm::Stage, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['name']).to eq('Proposta')
        expect(response.parsed_body['pipeline_id']).to eq(pipeline.id)
        expect(response.parsed_body['wip_limit']).to eq(5)

        created = Crm::Stage.find(response.parsed_body['id'])
        expect(created.account_id).to eq(account.id)
      end

      it 'returns unprocessable entity for an invalid probability' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
             params: { stage: { name: 'Invalida', probability: 200 } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
              params: { stage: { name: 'Novo' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to update stages' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
              params: { stage: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(stage.reload.name).to eq('Qualificacao')
      end
    end

    context 'when the user is an administrator' do
      it 'updates the stage' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
              params: { stage: { name: 'Qualificado', wip_limit: 3 } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(stage.reload.name).to eq('Qualificado')
        expect(stage.wip_limit).to eq(3)
      end

      it 'returns not found for a stage of another pipeline' do
        other_pipeline = create(:crm_pipeline, account: account)
        other_stage = create(:crm_stage, account: account, pipeline: other_pipeline)

        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{other_stage.id}",
              params: { stage: { name: 'Novo' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}"

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Stage.exists?(stage.id)).to be(true)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to delete stages' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Stage.exists?(stage.id)).to be(true)
      end
    end

    context 'when the user is an administrator' do
      it 'deletes a stage without deals' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
               headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(Crm::Stage.exists?(stage.id)).to be(false)
      end

      it 'returns unprocessable entity when the stage still holds deals' do
        create(:crm_deal, account: account, pipeline: pipeline, stage: stage)

        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
               headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
        expect(Crm::Stage.exists?(stage.id)).to be(true)
      end
    end
  end
end
