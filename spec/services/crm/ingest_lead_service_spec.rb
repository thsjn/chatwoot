require 'rails_helper'

describe Crm::IngestLeadService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) do
    create(:crm_pipeline, :default, account: account,
                                    settings: { 'inbox_ids' => [inbox.id], 'janela_dedupe_dias' => 30, 'moeda_padrao' => 'BRL' })
  end
  let!(:entry_stage) { create(:crm_stage, :entry, account: account, pipeline: pipeline, position: 1000) }
  let(:source) { create(:crm_source, account: account, kind: :api, inbox: inbox) }
  let(:params) { { name: 'Maria Souza', email: 'maria@exemplo.com' } }

  describe '#perform' do
    it 'creates the card at the bottom of the entry column' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: entry_stage, position: 5000)

      result = described_class.new(source: source, params: params).perform

      expect(result[:created]).to be(true)
      expect(result[:deal].position).to eq(6000)
    end

    it 'records the card as automated so the audit trail shows it was not opened by a person' do
      result = described_class.new(source: source, params: params).perform

      transition = result[:deal].stage_transitions.first
      expect(transition.from_stage_id).to be_nil
      expect(transition.automated).to be(true)
    end

    # This is the point of sharing `Crm::DealDedupe` with the conversation ingestion: a contact who
    # already opened a card through WhatsApp does not get a second one because the same person also
    # filled the form on the landing page.
    it 'reuses the card the conversation ingestion already opened for the contact' do
      contact = create(:contact, account: account, email: 'maria@exemplo.com')
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      Crm::IngestConversationService.new(conversation: conversation).perform
      existing_deal = Crm::Deal.last

      result = nil
      expect { result = described_class.new(source: source, params: params).perform }.not_to change(Crm::Deal, :count)

      expect(result[:created]).to be(false)
      expect(result[:deal].id).to eq(existing_deal.id)
    end

    it 'bumps the activity of the deduplicated card without rewriting its attribution' do
      first = described_class.new(source: source, params: params.merge(utm: { 'utm_source' => 'google' })).perform
      first[:deal].update_columns(last_activity_at: 3.days.ago)

      second = described_class.new(source: source, params: params.merge(utm: { 'utm_source' => 'meta' })).perform

      expect(second[:deal].utm).to eq({ 'utm_source' => 'google' })
      expect(second[:deal].last_activity_at).to be > 1.hour.ago
    end

    context 'when the account has no pipeline able to take the lead' do
      it 'fails loudly when every pipeline is archived' do
        pipeline.archive!

        expect { described_class.new(source: source, params: params).perform }
          .to raise_error(described_class::ConfigurationError) { |error| expect(error.code).to eq(:pipeline_not_found) }
      end

      it 'fails loudly when the pipeline has no stage to receive the card' do
        entry_stage.destroy!

        expect { described_class.new(source: source, params: params).perform }
          .to raise_error(described_class::ConfigurationError) { |error| expect(error.code).to eq(:pipeline_without_stages) }
      end
    end

    it 'fails loudly when the source has no inbox to register the contact in' do
      source.update!(inbox: nil)

      expect { described_class.new(source: source, params: params).perform }
        .to raise_error(described_class::ConfigurationError) { |error| expect(error.code).to eq(:source_without_inbox) }
    end
  end
end
