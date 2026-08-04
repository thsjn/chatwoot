require 'rails_helper'

describe Crm::IngestConversationService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }
  let(:pipeline) do
    create(:crm_pipeline, account: account,
                          settings: { 'inbox_ids' => [inbox.id], 'janela_dedupe_dias' => 30, 'moeda_padrao' => 'BRL' })
  end
  let!(:entry_stage) { create(:crm_stage, :entry, account: account, pipeline: pipeline, name: 'Novo', position: 1000) }
  let!(:second_stage) { create(:crm_stage, account: account, pipeline: pipeline, name: 'Qualificado', position: 2000) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  describe '#perform' do
    context 'when the pipeline has no inbox configured' do
      let(:pipeline) do
        create(:crm_pipeline, account: account, settings: { 'inbox_ids' => [], 'janela_dedupe_dias' => 30, 'moeda_padrao' => 'BRL' })
      end

      it 'does not create any deal' do
        expect { described_class.new(conversation: conversation).perform }.not_to change(Crm::Deal, :count)
      end

      it 'does not link the conversation' do
        expect { described_class.new(conversation: conversation).perform }.not_to change(Crm::DealConversation, :count)
      end
    end

    context 'when the conversation comes from an inbox that is not configured' do
      let(:conversation) { create(:conversation, account: account, inbox: other_inbox, contact: contact) }

      it 'ignores the conversation' do
        expect { described_class.new(conversation: conversation).perform }.not_to change(Crm::Deal, :count)
      end
    end

    context 'when the inbox is configured' do
      let!(:source) { create(:crm_source, account: account, kind: :inbox, inbox: inbox) }

      it 'creates the deal in the entry stage' do
        described_class.new(conversation: conversation).perform

        deal = Crm::Deal.last
        expect(deal.stage).to eq(entry_stage)
        expect(deal.pipeline).to eq(pipeline)
        expect(deal.contact).to eq(contact)
        expect(deal.status).to eq('open')
      end

      it 'fills the deal attributes from the conversation and the pipeline settings' do
        described_class.new(conversation: conversation).perform

        deal = Crm::Deal.last
        expect(deal.title).to eq('Maria Souza')
        expect(deal.currency).to eq('BRL')
        expect(deal.source_inbox_id).to eq(inbox.id)
        expect(deal.source_id).to eq(source.id)
        expect(deal.last_activity_at).to be_present
      end

      it 'links the conversation as the origin of the deal' do
        described_class.new(conversation: conversation).perform

        link = Crm::DealConversation.find_by(conversation: conversation)
        expect(link.is_origin).to be(true)
        expect(link.deal).to eq(Crm::Deal.last)
      end

      it 'puts the card at the bottom of the entry column' do
        create(:crm_deal, account: account, pipeline: pipeline, stage: entry_stage, position: 5000)

        described_class.new(conversation: conversation).perform

        expect(Crm::Deal.order(:id).last.position).to eq(5000 + Crm::Deal::POSITION_GAP)
      end

      it 'returns the counters' do
        expect(described_class.new(conversation: conversation).perform).to eq({ created: 1, linked: 0 })
      end

      it 'records the entry into the funnel as an automated transition' do
        described_class.new(conversation: conversation).perform

        transition = Crm::Deal.last.stage_transitions.chronological.first
        expect(transition).to have_attributes(from_stage_id: nil, to_stage_id: entry_stage.id, duration_seconds: nil, automated: true)
        expect(transition.user_id).to be_nil
      end

      context 'when the contact has no name' do
        let(:contact) { create(:contact, account: account, name: '', email: 'maria@example.com') }

        it 'falls back to the contact email' do
          described_class.new(conversation: conversation).perform

          expect(Crm::Deal.last.title).to eq('maria@example.com')
        end
      end

      context 'when the contact has no name, email nor phone number' do
        let(:contact) { create(:contact, account: account, name: '') }

        it 'falls back to the contact identifier' do
          described_class.new(conversation: conversation).perform

          expect(Crm::Deal.last.title).to eq("Contact ##{contact.id}")
        end
      end

      context 'when there is no source for the inbox' do
        let!(:source) { nil }

        it 'creates the deal without a source' do
          described_class.new(conversation: conversation).perform

          expect(Crm::Deal.last.source_id).to be_nil
        end
      end
    end

    # Two conversations of the same contact arriving together (routine on WhatsApp) would both read
    # "no deal yet" and both create a card. Real concurrency is not reproducible in a spec that runs
    # inside a single transaction, so what is asserted here is that the read-then-write is guarded
    # by a transaction scoped advisory lock keyed by the exact pair being deduplicated.
    describe 'dedupe serialisation' do
      let(:expected_lock_key) { Zlib.crc32("crm_ingest_deal_#{account.id}_#{pipeline.id}_#{contact.id}") }

      it 'takes a transaction advisory lock keyed by account, pipeline and contact' do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original

        described_class.new(conversation: conversation).perform

        expect(ActiveRecord::Base.connection).to have_received(:execute).with("SELECT pg_advisory_xact_lock(#{expected_lock_key})").once
      end

      it 'takes one lock per matching pipeline, so two pipelines never share a slot' do
        second_pipeline = create(:crm_pipeline, account: account,
                                                settings: { 'inbox_ids' => [inbox.id], 'janela_dedupe_dias' => 30 })
        create(:crm_stage, :entry, account: account, pipeline: second_pipeline, position: 1000)
        second_key = Zlib.crc32("crm_ingest_deal_#{account.id}_#{second_pipeline.id}_#{contact.id}")
        allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original

        described_class.new(conversation: conversation).perform

        expect(ActiveRecord::Base.connection).to have_received(:execute).with("SELECT pg_advisory_xact_lock(#{expected_lock_key})").once
        expect(ActiveRecord::Base.connection).to have_received(:execute).with("SELECT pg_advisory_xact_lock(#{second_key})").once
      end

      it 'does not lock anything on a dry run' do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original

        described_class.new(conversation: conversation, dry_run: true).perform

        expect(ActiveRecord::Base.connection).not_to have_received(:execute).with(/pg_advisory_xact_lock/)
      end
    end

    context 'when the contact already has an open deal inside the dedupe window' do
      let!(:existing_deal) do
        create(:crm_deal, account: account, pipeline: pipeline, stage: second_stage, contact: contact, last_activity_at: 5.days.ago)
      end

      it 'does not create a new card' do
        expect { described_class.new(conversation: conversation).perform }.not_to change(Crm::Deal, :count)
      end

      it 'links the conversation to the existing deal without marking it as origin' do
        described_class.new(conversation: conversation).perform

        link = Crm::DealConversation.find_by(conversation: conversation)
        expect(link.deal).to eq(existing_deal)
        expect(link.is_origin).to be(false)
      end

      it 'refreshes the last activity of the existing deal' do
        expect { described_class.new(conversation: conversation).perform }
          .to(change { existing_deal.reload.last_activity_at })
      end

      it 'returns the counters as a link' do
        expect(described_class.new(conversation: conversation).perform).to eq({ created: 0, linked: 1 })
      end
    end

    context 'when the existing deal is outside the dedupe window' do
      before do
        deal = create(:crm_deal, account: account, pipeline: pipeline, stage: second_stage, contact: contact)
        deal.update_columns(created_at: 90.days.ago, updated_at: 90.days.ago)
      end

      it 'creates a new card' do
        expect { described_class.new(conversation: conversation).perform }.to change(Crm::Deal, :count).by(1)
      end
    end

    context 'when the existing deal is not eligible for dedupe' do
      it 'creates a new card when the existing deal is already won' do
        create(:crm_deal, :won, account: account, pipeline: pipeline, stage: second_stage, contact: contact)

        expect { described_class.new(conversation: conversation).perform }.to change(Crm::Deal, :count).by(1)
      end

      it 'creates a new card when the existing deal is archived' do
        create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: second_stage, contact: contact)

        expect { described_class.new(conversation: conversation).perform }.to change(Crm::Deal, :count).by(1)
      end

      it 'creates a new card when the open deal belongs to another contact' do
        create(:crm_deal, account: account, pipeline: pipeline, stage: second_stage)

        expect { described_class.new(conversation: conversation).perform }.to change(Crm::Deal, :count).by(1)
      end
    end

    context 'when the service runs twice for the same conversation' do
      it 'does not duplicate the deal nor the link' do
        described_class.new(conversation: conversation).perform

        expect { described_class.new(conversation: conversation).perform }
          .to not_change(Crm::Deal, :count).and not_change(Crm::DealConversation, :count)
      end

      it 'returns zeroed counters on the second run' do
        described_class.new(conversation: conversation).perform

        expect(described_class.new(conversation: conversation).perform).to eq({ created: 0, linked: 0 })
      end
    end

    context 'when the pipeline is archived' do
      before { pipeline.archive! }

      it 'ignores the conversation' do
        expect { described_class.new(conversation: conversation).perform }.not_to change(Crm::Deal, :count)
      end
    end

    context 'when the inbox id is stored as a string in the settings' do
      let(:pipeline) do
        create(:crm_pipeline, account: account,
                              settings: { 'inbox_ids' => [inbox.id.to_s], 'janela_dedupe_dias' => 30, 'moeda_padrao' => 'BRL' })
      end

      it 'still matches the pipeline' do
        expect { described_class.new(conversation: conversation).perform }.to change(Crm::Deal, :count).by(1)
      end
    end

    context 'when dry_run is enabled' do
      it 'does not write anything' do
        expect { described_class.new(conversation: conversation, dry_run: true).perform }
          .to not_change(Crm::Deal, :count).and not_change(Crm::DealConversation, :count)
      end

      it 'reports the card it would create' do
        expect(described_class.new(conversation: conversation, dry_run: true).perform).to eq({ created: 1, linked: 0 })
      end

      it 'counts a second conversation of the same contact as a link' do
        keys = Set.new
        described_class.new(conversation: conversation, dry_run: true, simulated_deal_keys: keys).perform
        another = create(:conversation, account: account, inbox: inbox, contact: contact)

        expect(described_class.new(conversation: another, dry_run: true, simulated_deal_keys: keys).perform)
          .to eq({ created: 0, linked: 1 })
      end
    end
  end
end
