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
end
