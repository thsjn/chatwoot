require 'rails_helper'

RSpec.describe Crm::LostReasonPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:lost_reason) { create(:crm_lost_reason, account: account) }

  permissions :index?, :show? do
    it 'allows administrators' do
      expect(subject).to permit(administrator_context, lost_reason)
    end

    it 'allows agents' do
      expect(subject).to permit(agent_context, lost_reason)
    end
  end

  permissions :create?, :update?, :destroy? do
    it 'allows administrators' do
      expect(subject).to permit(administrator_context, lost_reason)
    end

    it 'denies agents' do
      expect(subject).not_to permit(agent_context, lost_reason)
    end
  end
end
