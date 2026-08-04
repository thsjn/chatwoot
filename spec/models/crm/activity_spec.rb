require 'rails_helper'

RSpec.describe Crm::Activity do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:deal) { create(:crm_deal, account: account) }

  describe 'cross account isolation' do
    it 'rejects a deal from another account' do
      activity = build(:crm_activity, account: account, deal: create(:crm_deal, account: other_account))

      expect(activity).not_to be_valid
      expect(activity.errors[:deal_id]).to include('must belong to the same account as the activity')
    end

    it 'rejects a user who is not a member of the account' do
      activity = build(:crm_activity, account: account, deal: deal, user: create(:user, account: other_account, role: :agent))

      expect(activity).not_to be_valid
      expect(activity.errors[:user_id]).to include('must be a member of the same account as the activity')
    end

    it 'accepts a user who is a member of the account' do
      expect(build(:crm_activity, account: account, deal: deal, user: create(:user, account: account, role: :agent))).to be_valid
    end
  end

  describe 'scopes' do
    it 'treats only scheduled and unfinished activities as pending' do
      pending_activity = create(:crm_activity, :task, deal: deal, due_at: 1.day.from_now)
      create(:crm_activity, :task, :completed, deal: deal, due_at: 1.day.from_now)
      create(:crm_activity, deal: deal, due_at: nil)

      expect(described_class.pending).to contain_exactly(pending_activity)
    end

    it 'returns only past due pending activities as overdue' do
      overdue = create(:crm_activity, :task, deal: deal, due_at: 1.hour.ago)
      create(:crm_activity, :task, deal: deal, due_at: 1.hour.from_now)
      create(:crm_activity, :task, :completed, deal: deal, due_at: 1.hour.ago)

      expect(described_class.overdue).to contain_exactly(overdue)
    end
  end

  describe '#complete!' do
    it 'marks the activity as completed' do
      activity = create(:crm_activity, :task, deal: deal)

      expect(activity).not_to be_completed
      activity.complete!
      expect(activity).to be_completed
      expect(described_class.completed).to include(activity)
    end
  end
end
