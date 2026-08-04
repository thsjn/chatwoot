require 'rails_helper'

describe Crm::IngestConversationJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }
  let(:pipeline) do
    create(:crm_pipeline, account: account,
                          settings: { 'inbox_ids' => [inbox.id], 'janela_dedupe_dias' => 30, 'moeda_padrao' => 'BRL' })
  end
  let!(:entry_stage) { create(:crm_stage, :entry, account: account, pipeline: pipeline, name: 'Novo', position: 1000) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  describe '#perform' do
    it 'creates the card through the ingestion service' do
      expect { described_class.perform_now(conversation) }.to change(Crm::Deal, :count).by(1)
      expect(Crm::Deal.last.stage).to eq(entry_stage)
    end

    it 'does not duplicate anything when retried' do
      described_class.perform_now(conversation)

      expect { described_class.perform_now(conversation) }
        .to not_change(Crm::Deal, :count).and not_change(Crm::DealConversation, :count)
    end
  end
end
