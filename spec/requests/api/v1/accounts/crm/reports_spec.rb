require 'rails_helper'

RSpec.describe 'CRM Reports API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:crm_pipeline, account: account) }

  # A four column funnel with known positions and probabilities, so every expected number below
  # can be checked by hand.
  let!(:novo) { create(:crm_stage, :entry, account: account, pipeline: pipeline, name: 'Novo', position: 0, probability: 10) }
  let!(:qualificacao) { create(:crm_stage, account: account, pipeline: pipeline, name: 'Qualificacao', position: 1, probability: 50) }
  let!(:proposta) { create(:crm_stage, account: account, pipeline: pipeline, name: 'Proposta', position: 2, probability: 50) }
  let!(:ganho) { create(:crm_stage, :won, account: account, pipeline: pipeline, name: 'Ganho', position: 3) }
  let!(:perdido) { create(:crm_stage, :lost, account: account, pipeline: pipeline, name: 'Perdido', position: 4) }

  let(:base_url) { "/api/v1/accounts/#{account.id}/crm/reports" }

  describe 'GET /crm/reports/funnel' do
    # Every deal is born in Novo, and creating it already records the transition into that stage,
    # so the trail below is the whole story of each card:
    # deal_a: Novo -> Qualificacao             (visited Novo, Qualificacao)
    # deal_b: Novo -> Qualificacao -> Proposta (visited Novo, Qualificacao, Proposta)
    # deal_c: created in Novo, never moved     (visited Novo)
    let!(:deal_a) { create(:crm_deal, account: account, pipeline: pipeline, stage: novo) }
    let!(:deal_b) { create(:crm_deal, account: account, pipeline: pipeline, stage: novo) }
    let!(:deal_c) { create(:crm_deal, account: account, pipeline: pipeline, stage: novo) }

    before do
      create(:crm_stage_transition, deal: deal_a, from_stage: novo, to_stage: qualificacao, duration_seconds: 100)
      deal_a.update!(stage: qualificacao)
      create(:crm_stage_transition, deal: deal_b, from_stage: novo, to_stage: qualificacao, duration_seconds: 200)
      create(:crm_stage_transition, deal: deal_b, from_stage: qualificacao, to_stage: proposta, duration_seconds: 60)
      deal_b.update!(stage: proposta)
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "#{base_url}/funnel", params: { pipeline_id: pipeline.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'counts every deal that reached each stage and how many moved past it' do
      get "#{base_url}/funnel", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload'].index_by { |row| row['name'] }

      # 3 deals passed through Novo, 2 of them (a and b) moved forward -> 2/3
      expect(payload['Novo']).to include('entered_count' => 3, 'advanced_count' => 2, 'conversion_rate' => 66.67)
      # a and b reached Qualificacao, only b moved on -> 1/2
      expect(payload['Qualificacao']).to include('entered_count' => 2, 'advanced_count' => 1, 'conversion_rate' => 50.0)
      # b is sitting in Proposta and never left it
      expect(payload['Proposta']).to include('entered_count' => 1, 'advanced_count' => 0, 'conversion_rate' => 0.0)
      # untouched stages still show up, with zeros
      expect(payload['Ganho']).to include('entered_count' => 0, 'advanced_count' => 0)
    end

    it 'is readable by an agent' do
      get "#{base_url}/funnel", params: { pipeline_id: pipeline.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    # The top of the funnel used to be inferred from the origin stage of the first recorded move,
    # so it depended on the card having moved at least once. It now reads the transition written
    # when the deal was created, which every deal has.
    it 'counts a deal created straight into a middle stage in that stage and not in the ones before it' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: proposta)

      get "#{base_url}/funnel", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(payload['Novo']['entered_count']).to eq(3)
      expect(payload['Qualificacao']['entered_count']).to eq(2)
      expect(payload['Proposta']['entered_count']).to eq(2)
    end

    it 'counts a deal ingested from a conversation in the entry stage of its pipeline' do
      inbox = create(:inbox, account: account)
      pipeline.update!(settings: pipeline.settings.merge('inbox_ids' => [inbox.id]))
      conversation = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))
      Crm::IngestConversationService.new(conversation: conversation).perform

      get "#{base_url}/funnel", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(payload['Novo']['entered_count']).to eq(4)
    end

    it 'ignores archived deals' do
      deal_c.archive!

      get "#{base_url}/funnel", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(payload['Novo']).to include('entered_count' => 2, 'advanced_count' => 2, 'conversion_rate' => 100.0)
    end

    it 'ignores deals of another account sitting in an identical funnel' do
      foreign_pipeline = create(:crm_pipeline, account: other_account)
      foreign_stage = create(:crm_stage, account: other_account, pipeline: foreign_pipeline, position: 0)
      create_list(:crm_deal, 4, account: other_account, pipeline: foreign_pipeline, stage: foreign_stage)

      get "#{base_url}/funnel", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(payload['Novo']['entered_count']).to eq(3)
      expect(response.parsed_body['payload'].pluck('name')).to contain_exactly('Novo', 'Qualificacao', 'Proposta', 'Ganho', 'Perdido')
    end

    it 'keeps only the deals created inside the date range' do
      deal_c.update!(created_at: 40.days.ago)

      get "#{base_url}/funnel",
          params: { pipeline_id: pipeline.id, since: 10.days.ago.to_i.to_s, until: 1.day.from_now.to_i.to_s },
          headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(payload['Novo']['entered_count']).to eq(2)
    end
  end

  describe 'GET /crm/reports/stage_durations' do
    let!(:deal_a) { create(:crm_deal, account: account, pipeline: pipeline, stage: qualificacao) }
    let!(:deal_b) { create(:crm_deal, account: account, pipeline: pipeline, stage: proposta) }

    before do
      # `duration_seconds` is the time spent in the stage being LEFT, so these belong to Novo.
      create(:crm_stage_transition, deal: deal_a, from_stage: novo, to_stage: qualificacao, duration_seconds: 100)
      create(:crm_stage_transition, deal: deal_b, from_stage: novo, to_stage: qualificacao, duration_seconds: 200)
      create(:crm_stage_transition, deal: deal_b, from_stage: qualificacao, to_stage: proposta, duration_seconds: 60)
    end

    it 'averages the recorded duration of each stage' do
      get "#{base_url}/stage_durations", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload'].index_by { |row| row['name'] }

      expect(payload['Novo']).to include('avg_duration_seconds' => 150, 'transitions_count' => 2)
      expect(payload['Qualificacao']).to include('avg_duration_seconds' => 60, 'transitions_count' => 1)
      # Nobody has left Proposta yet.
      expect(payload['Proposta']).to include('avg_duration_seconds' => nil, 'transitions_count' => 0)
    end

    it 'ignores archived deals' do
      deal_b.archive!

      get "#{base_url}/stage_durations", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(payload['Novo']).to include('avg_duration_seconds' => 100, 'transitions_count' => 1)
      expect(payload['Qualificacao']).to include('avg_duration_seconds' => nil, 'transitions_count' => 0)
    end

    it 'ignores transitions of another account' do
      foreign_pipeline = create(:crm_pipeline, account: other_account)
      foreign_from = create(:crm_stage, account: other_account, pipeline: foreign_pipeline, position: 0)
      foreign_to = create(:crm_stage, account: other_account, pipeline: foreign_pipeline, position: 1)
      foreign_deal = create(:crm_deal, account: other_account, pipeline: foreign_pipeline, stage: foreign_to)
      create(:crm_stage_transition, deal: foreign_deal, from_stage: foreign_from, to_stage: foreign_to, duration_seconds: 99_999)

      get "#{base_url}/stage_durations", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(payload['Novo']).to include('avg_duration_seconds' => 150)
    end
  end

  describe 'GET /crm/reports/sales_cycle' do
    before do
      # Won: 10 days (864000s) and 20 days (1728000s) -> average 15 days (1296000s)
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won,
                        created_at: 40.days.ago, closed_at: 30.days.ago)
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won,
                        created_at: 40.days.ago, closed_at: 20.days.ago)
      # Lost: 5 days (432000s)
      create(:crm_deal, account: account, pipeline: pipeline, stage: perdido, status: :lost,
                        created_at: 25.days.ago, closed_at: 20.days.ago)
      # Still open, must not count anywhere.
      create(:crm_deal, account: account, pipeline: pipeline, stage: qualificacao, created_at: 40.days.ago)
    end

    it 'averages the time from creation to closing, split by outcome' do
      get "#{base_url}/sales_cycle", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']

      expect(payload['won']).to eq({ 'avg_cycle_seconds' => 15.days.to_i, 'deals_count' => 2 })
      expect(payload['lost']).to eq({ 'avg_cycle_seconds' => 5.days.to_i, 'deals_count' => 1 })
    end

    it 'ignores archived deals' do
      Crm::Deal.where(account_id: account.id, status: :won).last.archive!

      get "#{base_url}/sales_cycle", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['won']).to eq({ 'avg_cycle_seconds' => 10.days.to_i, 'deals_count' => 1 })
    end

    it 'keeps only the deals closed inside the date range' do
      get "#{base_url}/sales_cycle",
          params: { pipeline_id: pipeline.id, since: 25.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
          headers: admin.create_new_auth_token, as: :json

      # The deal closed 30 days ago falls out; only the 20 day one remains.
      expect(response.parsed_body['payload']['won']).to eq({ 'avg_cycle_seconds' => 20.days.to_i, 'deals_count' => 1 })
    end

    it 'ignores deals of another account' do
      foreign_pipeline = create(:crm_pipeline, account: other_account)
      foreign_stage = create(:crm_stage, :won, account: other_account, pipeline: foreign_pipeline)
      create(:crm_deal, account: other_account, pipeline: foreign_pipeline, stage: foreign_stage, status: :won,
                        created_at: 100.days.ago, closed_at: 1.day.ago)

      get "#{base_url}/sales_cycle", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['won']['deals_count']).to eq(2)
    end
  end

  describe 'GET /crm/reports/forecast' do
    before do
      # March: 1000,00 at 50% + 2000,00 at 50% -> raw 300000, weighted 150000
      create(:crm_deal, account: account, pipeline: pipeline, stage: qualificacao,
                        value_cents: 100_000, expected_close_on: '2026-03-10')
      create(:crm_deal, account: account, pipeline: pipeline, stage: proposta,
                        value_cents: 200_000, expected_close_on: '2026-03-20')
      # April: 3000,00 at 10% -> raw 300000, weighted 30000
      create(:crm_deal, account: account, pipeline: pipeline, stage: novo,
                        value_cents: 300_000, expected_close_on: '2026-04-05')
      # Closed and archived deals are out of the forecast.
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won,
                        value_cents: 999_999, expected_close_on: '2026-03-15', closed_at: Time.current)
      create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: proposta,
                                   value_cents: 888_888, expected_close_on: '2026-03-15')
    end

    it 'sums the open pipeline per month, weighted by the stage probability' do
      get "#{base_url}/forecast", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']

      expect(payload).to eq(
        [
          { 'period' => '2026-03-01', 'deals_count' => 2, 'value_cents' => 300_000, 'weighted_value_cents' => 150_000 },
          { 'period' => '2026-04-01', 'deals_count' => 1, 'value_cents' => 300_000, 'weighted_value_cents' => 30_000 }
        ]
      )
    end

    it 'buckets the deals without an expected close date under a null period' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: proposta, value_cents: 40_000, expected_close_on: nil)

      get "#{base_url}/forecast", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].last).to eq(
        { 'period' => nil, 'deals_count' => 1, 'value_cents' => 40_000, 'weighted_value_cents' => 20_000 }
      )
    end

    it 'ignores the open pipeline of another account' do
      foreign_pipeline = create(:crm_pipeline, account: other_account)
      foreign_stage = create(:crm_stage, account: other_account, pipeline: foreign_pipeline, probability: 100)
      create(:crm_deal, account: other_account, pipeline: foreign_pipeline, stage: foreign_stage,
                        value_cents: 500_000, expected_close_on: '2026-03-10')

      get "#{base_url}/forecast", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].first['value_cents']).to eq(300_000)
    end
  end

  describe 'GET /crm/reports/sources' do
    let(:instagram) { create(:crm_source, account: account, name: 'Instagram') }
    let(:indicacao) { create(:crm_source, account: account, name: 'Indicacao') }

    before do
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won,
                        source: instagram, value_cents: 50_000, closed_at: 2.days.ago)
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won,
                        source: instagram, value_cents: 70_000, closed_at: 2.days.ago)
      create(:crm_deal, account: account, pipeline: pipeline, stage: perdido, status: :lost,
                        source: instagram, value_cents: 30_000, closed_at: 2.days.ago)
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won,
                        source: indicacao, value_cents: 10_000, closed_at: 2.days.ago)
      # Open deals never show up here.
      create(:crm_deal, account: account, pipeline: pipeline, stage: proposta, source: indicacao, value_cents: 900_000)
    end

    it 'splits wins and losses per source, ordered by the money won' do
      get "#{base_url}/sources", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']

      expect(payload.first['source']).to include('name' => 'Instagram')
      expect(payload.first).to include(
        'won_count' => 2, 'won_value_cents' => 120_000,
        'lost_count' => 1, 'lost_value_cents' => 30_000,
        'win_rate' => 66.67
      )
      expect(payload.second['source']).to include('name' => 'Indicacao')
      expect(payload.second).to include('won_count' => 1, 'won_value_cents' => 10_000, 'lost_count' => 0, 'win_rate' => 100.0)
    end

    it 'reports the deals closed without a source under a null source' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won,
                        source: nil, value_cents: 5_000, closed_at: 2.days.ago)

      get "#{base_url}/sources", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      untagged = response.parsed_body['payload'].find { |row| row['source'].nil? }
      expect(untagged).to include('won_count' => 1, 'won_value_cents' => 5_000)
    end

    it 'keeps only the deals closed inside the date range' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won,
                        source: indicacao, value_cents: 400_000, closed_at: 90.days.ago)

      get "#{base_url}/sources",
          params: { pipeline_id: pipeline.id, since: 10.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
          headers: admin.create_new_auth_token, as: :json

      indicacao_row = response.parsed_body['payload'].find { |row| row['source'] && row['source']['name'] == 'Indicacao' }
      expect(indicacao_row['won_value_cents']).to eq(10_000)
    end

    it 'ignores archived deals and deals of another account' do
      Crm::Deal.where(account_id: account.id, source_id: indicacao.id, status: :won).first.archive!
      foreign_source = create(:crm_source, account: other_account, name: 'Instagram')
      foreign_pipeline = create(:crm_pipeline, account: other_account)
      foreign_stage = create(:crm_stage, :won, account: other_account, pipeline: foreign_pipeline)
      create(:crm_deal, account: other_account, pipeline: foreign_pipeline, stage: foreign_stage, status: :won,
                        source: foreign_source, value_cents: 700_000, closed_at: 2.days.ago)

      get "#{base_url}/sources", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload.pluck('won_value_cents')).to eq([120_000])
      expect(payload.first['source']).to include('name' => 'Instagram')
    end
  end

  describe 'GET /crm/reports/loss_reasons' do
    let(:preco) { create(:crm_lost_reason, account: account, name: 'Preco') }
    let(:concorrente) { create(:crm_lost_reason, account: account, name: 'Concorrente') }

    before do
      create(:crm_deal, account: account, pipeline: pipeline, stage: perdido, status: :lost,
                        lost_reason: preco, value_cents: 30_000, closed_at: 2.days.ago)
      create(:crm_deal, account: account, pipeline: pipeline, stage: perdido, status: :lost,
                        lost_reason: preco, value_cents: 20_000, closed_at: 2.days.ago)
      create(:crm_deal, account: account, pipeline: pipeline, stage: perdido, status: :lost,
                        lost_reason: concorrente, value_cents: 15_000, closed_at: 2.days.ago)
      create(:crm_deal, account: account, pipeline: pipeline, stage: ganho, status: :won, value_cents: 999_999, closed_at: 2.days.ago)
    end

    it 'counts and sums the lost deals per reason, most frequent first' do
      get "#{base_url}/loss_reasons", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']

      expect(payload.first['lost_reason']).to include('name' => 'Preco')
      expect(payload.first).to include('deals_count' => 2, 'value_cents' => 50_000)
      expect(payload.second['lost_reason']).to include('name' => 'Concorrente')
      expect(payload.second).to include('deals_count' => 1, 'value_cents' => 15_000)
    end

    it 'ignores archived deals' do
      Crm::Deal.where(account_id: account.id, lost_reason_id: preco.id).first.archive!

      get "#{base_url}/loss_reasons", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      preco_row = response.parsed_body['payload'].find { |row| row['lost_reason']['name'] == 'Preco' }
      expect(preco_row).to include('deals_count' => 1, 'value_cents' => 20_000)
    end

    it 'ignores lost deals of another account' do
      foreign_pipeline = create(:crm_pipeline, account: other_account)
      foreign_stage = create(:crm_stage, :lost, account: other_account, pipeline: foreign_pipeline)
      foreign_reason = create(:crm_lost_reason, account: other_account, name: 'Preco')
      create(:crm_deal, account: other_account, pipeline: foreign_pipeline, stage: foreign_stage, status: :lost,
                        lost_reason: foreign_reason, value_cents: 400_000, closed_at: 2.days.ago)

      get "#{base_url}/loss_reasons", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].sum { |row| row['value_cents'] }).to eq(65_000)
    end
  end

  describe 'GET /crm/reports/deals_export' do
    let(:contact) { create(:contact, account: account, name: 'Fulano de Tal') }
    let(:source) { create(:crm_source, account: account, name: 'Instagram') }
    let(:reason) { create(:crm_lost_reason, account: account, name: 'Preco') }

    before do
      create(:crm_deal, account: account, pipeline: pipeline, stage: perdido, status: :lost, title: 'Negocio perdido',
                        contact: contact, owner: agent, source: source, lost_reason: reason,
                        value_cents: 123_456, currency: 'BRL', closed_at: 2.days.ago)
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "#{base_url}/deals_export.csv", params: { pipeline_id: pipeline.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'exports the filtered deals as CSV' do
      get "#{base_url}/deals_export.csv", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to include('text/csv')

      rows = CSV.parse(response.body)
      expect(rows.first).to eq(%w[title value currency stage status contact owner source lost_reason created_at closed_at])
      expect(rows.second[0..8]).to eq(
        ['Negocio perdido', '1234.56', 'BRL', 'Perdido', 'lost', 'Fulano de Tal', agent.available_name, 'Instagram', 'Preco']
      )
    end

    it 'does not export archived deals nor deals of another account' do
      create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: proposta, title: 'Arquivado')
      foreign_pipeline = create(:crm_pipeline, account: other_account)
      create(:crm_deal, account: other_account, pipeline: foreign_pipeline, title: 'De outra conta',
                        stage: create(:crm_stage, account: other_account, pipeline: foreign_pipeline))

      get "#{base_url}/deals_export.csv", params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token

      titles = CSV.parse(response.body).drop(1).pluck(0)
      expect(titles).to eq(['Negocio perdido'])
    end

    it 'applies the status filter' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: proposta, title: 'Em aberto')

      get "#{base_url}/deals_export.csv", params: { pipeline_id: pipeline.id, status: 'open' }, headers: admin.create_new_auth_token

      titles = CSV.parse(response.body).drop(1).pluck(0)
      expect(titles).to eq(['Em aberto'])
    end
  end

  describe 'visibility of an agent on a pipeline restricted by owner' do
    let(:restricted_pipeline) { create(:crm_pipeline, :restricted_by_owner, account: account) }
    let!(:restricted_won) { create(:crm_stage, :won, account: account, pipeline: restricted_pipeline, position: 1) }

    before do
      create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_won, status: :won,
                        owner: agent, value_cents: 10_000, closed_at: 1.day.ago)
      create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_won, status: :won,
                        owner: create(:user, account: account, role: :agent), value_cents: 990_000, closed_at: 1.day.ago)
    end

    # The metrics reuse `Crm::DealPolicy::Scope`: an aggregate must never reveal what the board
    # already hides, otherwise the restriction would be readable straight off the totals.
    it 'only aggregates the deals the agent can see' do
      get "#{base_url}/sources", params: { pipeline_id: restricted_pipeline.id }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].sum { |row| row['won_value_cents'] }).to eq(10_000)
    end

    it 'aggregates every deal for an administrator' do
      get "#{base_url}/sources", params: { pipeline_id: restricted_pipeline.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].sum { |row| row['won_value_cents'] }).to eq(1_000_000)
    end
  end
end
