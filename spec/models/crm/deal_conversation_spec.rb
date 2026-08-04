require 'rails_helper'

RSpec.describe Crm::DealConversation do
  let(:account) { create(:account) }
  let(:deal) { create(:crm_deal, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe 'uniqueness of the deal and conversation pair' do
    before { create(:crm_deal_conversation, deal: deal, conversation: conversation) }

    it 'rejects a duplicate link' do
      duplicate = build(:crm_deal_conversation, deal: deal, conversation: conversation)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:conversation_id]).to be_present
    end

    it 'is enforced by the database index even when validations are skipped' do
      duplicate = build(:crm_deal_conversation, deal: deal, conversation: conversation)

      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same conversation on another deal' do
      expect(build(:crm_deal_conversation, deal: create(:crm_deal, account: account), conversation: conversation)).to be_valid
    end

    it 'allows another conversation on the same deal' do
      expect(build(:crm_deal_conversation, deal: deal, conversation: create(:conversation, account: account))).to be_valid
    end
  end

  describe 'cross account isolation' do
    it 'rejects a conversation from another account' do
      link = build(:crm_deal_conversation, deal: deal, conversation: create(:conversation, account: create(:account)))

      expect(link).not_to be_valid
      expect(link.errors[:conversation_id]).to include('must belong to the same account as the deal')
    end
  end

  describe '.origin' do
    it 'returns only the links flagged as origin' do
      origin = create(:crm_deal_conversation, :origin, deal: deal, conversation: conversation)
      create(:crm_deal_conversation, deal: deal, conversation: create(:conversation, account: account))

      expect(described_class.origin).to contain_exactly(origin)
    end
  end
end
