require 'rails_helper'

RSpec.describe 'CRM Sources API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }
  let!(:source) { create(:crm_source, account: account, name: 'Landing arroba', kind: :landing, token_digest: 'super-secret-digest') }

  describe 'GET /api/v1/accounts/{account.id}/crm/sources' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/sources"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user belongs to another account' do
      it 'does not expose this account resources' do
        get "/api/v1/accounts/#{account.id}/crm/sources",
            headers: foreign_admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      let!(:foreign_source) { create(:crm_source, account: other_account) }

      it 'lists only the sources of the current account' do
        get "/api/v1/accounts/#{account.id}/crm/sources",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to eq([source.id])
        expect(ids).not_to include(foreign_source.id)
      end

      it 'never serializes the token digest' do
        get "/api/v1/accounts/#{account.id}/crm/sources",
            headers: admin.create_new_auth_token, as: :json

        expect(response.body).not_to include('super-secret-digest')
        expect(response.parsed_body['payload'].first.keys).not_to include('token_digest')
      end

      it 'is readable by an agent' do
        get "/api/v1/accounts/#{account.id}/crm/sources",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      # A source the account turned off stays on the deals that already carry it, but it must not
      # show up in the board filter and in the drawer select as if it were still usable.
      it 'hides the inactive sources by default' do
        inactive = create(:crm_source, :inactive, account: account)

        get "/api/v1/accounts/#{account.id}/crm/sources",
            headers: agent.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to include(source.id)
        expect(ids).not_to include(inactive.id)
      end

      it 'lists the inactive sources when the administration asks for them' do
        inactive = create(:crm_source, :inactive, account: account)

        get "/api/v1/accounts/#{account.id}/crm/sources",
            params: { include_inactive: true }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to include(inactive.id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/sources/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the source' do
        get "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(source.id)
        expect(response.parsed_body['name']).to eq('Landing arroba')
        expect(response.parsed_body).not_to have_key('token_digest')
      end

      it 'returns not found for a source of another account' do
        foreign_source = create(:crm_source, account: other_account)

        get "/api/v1/accounts/#{account.id}/crm/sources/#{foreign_source.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/sources' do
    let(:valid_params) { { source: { name: 'Webhook n8n', kind: 'n8n', identifier: 'n8n-leads', active: true } } }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/sources", params: valid_params, as: :json
        end.not_to change(Crm::Source, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to create sources' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/sources",
               params: valid_params, headers: agent.create_new_auth_token, as: :json
        end.not_to change(Crm::Source, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an administrator' do
      it 'creates the source' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/sources",
               params: valid_params, headers: admin.create_new_auth_token, as: :json
        end.to change(Crm::Source, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['name']).to eq('Webhook n8n')
        expect(response.parsed_body['kind']).to eq('n8n')
        expect(response.parsed_body.keys).not_to include('token_digest')
        expect(Crm::Source.find(response.parsed_body['id']).account_id).to eq(account.id)
      end

      it 'returns unprocessable entity for a duplicated name' do
        post "/api/v1/accounts/#{account.id}/crm/sources",
             params: { source: { name: source.name } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/sources/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}",
              params: { source: { name: 'Novo' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to update sources' do
        patch "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}",
              params: { source: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(source.reload.name).to eq('Landing arroba')
      end
    end

    context 'when the user is an administrator' do
      it 'updates the source' do
        patch "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}",
              params: { source: { name: 'Landing e-book', active: false } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['active']).to be(false)
        expect(source.reload.name).to eq('Landing e-book')
      end

      it 'returns not found for a source of another account' do
        foreign_source = create(:crm_source, account: other_account)

        patch "/api/v1/accounts/#{account.id}/crm/sources/#{foreign_source.id}",
              params: { source: { name: 'Novo' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/sources/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}"

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Source.exists?(source.id)).to be(true)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to delete sources' do
        delete "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Source.exists?(source.id)).to be(true)
      end
    end

    context 'when the user is an administrator' do
      it 'deletes the source and nullifies it on the deals' do
        deal = create(:crm_deal, account: account, source: source)

        delete "/api/v1/accounts/#{account.id}/crm/sources/#{source.id}",
               headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(Crm::Source.exists?(source.id)).to be(false)
        expect(deal.reload.source_id).to be_nil
      end
    end
  end
end
