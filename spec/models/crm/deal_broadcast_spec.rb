require 'rails_helper'

RSpec.describe Crm::Deal do
  let(:account) { create(:account) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:stage) { create(:crm_stage, account: account, pipeline: pipeline, position: 0) }
  let(:next_stage) { create(:crm_stage, account: account, pipeline: pipeline, position: 1) }
  let(:contact) { create(:contact, account: account) }

  describe 'realtime events' do
    # The dispatcher is shared by every model, so it is spied instead of mocked: a contact or a
    # stage created along the way publishes its own events and must not fail the example.
    before { allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original }

    context 'when the account has the CRM module disabled' do
      let(:account) { create(:account, crm_kanban: false) }

      it 'does not publish card events' do
        deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact)
        deal.update!(title: 'Fazenda Santa Clara')
        deal.archive!

        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(/\Acrm_deal\./, anything, deal: deal)
      end
    end

    it 'dispatches crm_deal.created when a card enters the board' do
      deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('crm_deal.created', anything, deal: deal)
    end

    context 'with an existing deal' do
      let!(:deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact, position: 1000) }

      it 'dispatches crm_deal.moved when the stage changes' do
        deal.update!(stage: next_stage)

        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('crm_deal.moved', anything, deal: deal)
      end

      it 'dispatches crm_deal.moved when only the position changes' do
        deal.update!(position: 2000)

        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('crm_deal.moved', anything, deal: deal)
      end

      it 'dispatches crm_deal.updated for a plain edit' do
        deal.update!(title: 'Fazenda Santa Clara')

        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('crm_deal.updated', anything, deal: deal)
        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('crm_deal.moved', anything, deal: deal)
      end

      it 'dispatches crm_deal.archived when the card leaves the board' do
        deal.archive!

        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('crm_deal.archived', anything, deal: deal)
      end

      it 'dispatches crm_deal.updated when the card is restored, carrying a null archived_at' do
        deal.archive!
        deal.unarchive!

        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('crm_deal.updated', anything, deal: deal)
        expect(deal.push_event_data[:archived_at]).to be_nil
      end
    end
  end

  describe '#push_event_data' do
    let(:owner) { create(:user, account: account, role: :agent) }
    let(:deal) do
      create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact, owner: owner, value_cents: 250_000)
    end

    it 'carries the board card' do
      expect(deal.push_event_data).to include(
        id: deal.id, pipeline_id: pipeline.id, stage_id: stage.id,
        status: 'open', value_cents: 250_000, lock_version: deal.lock_version
      )
      expect(deal.push_event_data[:contact]).to include(id: contact.id)
      expect(deal.push_event_data[:owner]).to include(id: owner.id)
    end

    # The store merges this payload over the card it already has, so a relation that was cleared
    # has to arrive as an explicit null instead of being omitted.
    it 'reports the empty relations as null so the board can clear them' do
      deal.update!(owner: nil)

      expect(deal.push_event_data).to include(owner: nil, team: nil, source: nil, lost_reason: nil)
    end
  end

  # The payload is an ARGUMENT of `ActionCableBroadcastJob`, and Sidekiq's client refuses to enqueue
  # a job whose arguments are not native JSON types. That check never ran here before: the test
  # environment enqueues with the `:test` adapter, which serializes nothing, so a payload carrying
  # the `BigDecimal` of `crm_deals.position` passed every example and still 500'd every deal write
  # in staging — after the row had already been committed, since the dispatch is `after_*_commit`.
  #
  # So these examples do not reimplement the rule: they hand the payload to the real Sidekiq client
  # (in fake mode, so nothing touches Redis) and let `Sidekiq::JobUtil#verify_json` walk it, which is
  # the same recursive native-JSON-type check the deploy runs.
  describe '#push_event_data as a job argument' do
    let(:enqueue_broadcast) do
      lambda do |payload|
        previous_adapter = ActiveJob::Base.queue_adapter
        ActiveJob::Base.queue_adapter = :sidekiq
        begin
          Sidekiq::Testing.fake! { ActionCableBroadcastJob.perform_later(['pubsub-token'], 'crm_deal.updated', payload) }
        ensure
          Sidekiq::Queues.clear_all
          ActiveJob::Base.queue_adapter = previous_adapter
        end
      end
    end

    # A card dropped between two neighbours gets the average of their positions, so a fractional
    # `position` is the normal state of a board that has been used, not an edge case.
    it 'enqueues a card whose position is fractional' do
      deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact, position: 1234.5)

      expect { enqueue_broadcast.call(deal.push_event_data) }.not_to raise_error
      expect(deal.push_event_data[:position]).to eq(1234.5).and be_a(Float)
    end

    # `custom_attributes` is jsonb of free content: whatever the account defines as a deal field
    # ends up inside the payload, so the normalization has to reach into it and not only the columns.
    it 'enqueues a card whose custom attributes carry a number and a date' do
      create(:custom_attribute_definition, account: account, attribute_model: :deal_attribute,
                                           attribute_key: 'hectares', attribute_display_type: :number)
      create(:custom_attribute_definition, account: account, attribute_model: :deal_attribute,
                                           attribute_key: 'visita_em', attribute_display_type: :date)
      deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact,
                               custom_attributes: { 'hectares' => 1250.75, 'visita_em' => '2026-08-20' })

      expect { enqueue_broadcast.call(deal.push_event_data) }.not_to raise_error
      expect(deal.push_event_data[:custom_attributes]).to eq('hectares' => 1250.75, 'visita_em' => '2026-08-20')
    end

    it 'enqueues a card whose utm is populated' do
      deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact,
                               utm: { 'source' => 'meta', 'campaign_id' => 120_215_000, 'spend' => 42.5 })

      expect { enqueue_broadcast.call(deal.push_event_data) }.not_to raise_error
    end

    # `expected_close_on` is a `date` column, so `attributes` hands back a `Date` object. It only
    # survived the wire because ActiveJob happens to have a serializer for it; the board reads the
    # same "YYYY-MM-DD" string the jbuilder partial serves, and the store MERGES this over the card.
    it 'enqueues a card with an expected close date, as the string the board already reads' do
      deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact,
                               expected_close_on: Date.new(2026, 8, 20))

      expect { enqueue_broadcast.call(deal.push_event_data) }.not_to raise_error
      expect(deal.push_event_data[:expected_close_on]).to eq('2026-08-20')
    end
  end
end
