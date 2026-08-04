require 'rails_helper'

describe Crm::BackfillJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }
  let(:pipeline) do
    create(:crm_pipeline, account: account,
                          settings: { 'inbox_ids' => [inbox.id], 'janela_dedupe_dias' => 30, 'moeda_padrao' => 'BRL' })
  end
  let!(:entry_stage) { create(:crm_stage, :entry, account: account, pipeline: pipeline, name: 'Novo', position: 1000) }

  describe '#perform' do
    context 'when no pipeline has inboxes configured' do
      let(:pipeline) do
        create(:crm_pipeline, account: account, settings: { 'inbox_ids' => [], 'janela_dedupe_dias' => 30, 'moeda_padrao' => 'BRL' })
      end

      before { create(:conversation, account: account, inbox: inbox, contact: contact) }

      it 'creates nothing and reports zero' do
        report = nil

        expect { report = described_class.perform_now(account, dry_run: false) }.not_to change(Crm::Deal, :count)
        expect(report[:totals]).to eq({ created: 0, linked: 0 })
      end
    end

    context 'when running in dry_run (the default)' do
      before do
        entry_stage
        create(:conversation, account: account, inbox: inbox, contact: contact)
        create(:conversation, account: account, inbox: inbox, contact: contact)
        create(:conversation, account: account, inbox: other_inbox, contact: contact)
      end

      it 'does not write anything' do
        expect { described_class.perform_now(account) }
          .to not_change(Crm::Deal, :count).and not_change(Crm::DealConversation, :count)
      end

      it 'reports one card and one link for the configured inbox only' do
        report = described_class.perform_now(account)

        expect(report[:dry_run]).to be(true)
        expect(report[:totals]).to eq({ created: 1, linked: 1 })
        expect(report[:by_inbox]).to eq({ inbox.id => { created: 1, linked: 1 } })
      end
    end

    context 'when running for real' do
      before do
        entry_stage
        create(:conversation, account: account, inbox: inbox, contact: contact)
        create(:conversation, account: account, inbox: inbox, contact: contact)
      end

      it 'creates a single card and links both conversations' do
        expect { described_class.perform_now(account, dry_run: false) }.to change(Crm::Deal, :count).by(1)

        deal = Crm::Deal.last
        expect(deal.stage).to eq(entry_stage)
        expect(deal.deal_conversations.count).to eq(2)
        expect(deal.deal_conversations.origin.count).to eq(1)
      end

      it 'reports what it did' do
        report = described_class.perform_now(account, dry_run: false)

        expect(report[:totals]).to eq({ created: 1, linked: 1 })
      end

      it 'is idempotent across runs' do
        described_class.perform_now(account, dry_run: false)

        expect { described_class.perform_now(account, dry_run: false) }
          .to not_change(Crm::Deal, :count).and not_change(Crm::DealConversation, :count)
      end

      it 'reports zero on a dry run made after a real run' do
        described_class.perform_now(account, dry_run: false)

        expect(described_class.perform_now(account)[:totals]).to eq({ created: 0, linked: 0 })
      end
    end

    context 'when the conversation is older than the window' do
      before do
        entry_stage
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
        conversation.update_columns(created_at: 200.days.ago)
      end

      it 'skips it with the default window' do
        expect { described_class.perform_now(account, dry_run: false) }.not_to change(Crm::Deal, :count)
      end

      it 'ingests it with a wider window' do
        expect { described_class.perform_now(account, dry_run: false, window_days: 365) }.to change(Crm::Deal, :count).by(1)
      end
    end
  end
end
