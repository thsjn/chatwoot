require 'rails_helper'

RSpec.describe Crm::SourcePolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:source) { create(:crm_source, account: account) }

  permissions :index?, :show? do
    it 'allows administrators' do
      expect(subject).to permit(administrator_context, source)
    end

    it 'allows agents' do
      expect(subject).to permit(agent_context, source)
    end
  end

  permissions :create?, :update?, :destroy?, :regenerate_token? do
    it 'allows administrators' do
      expect(subject).to permit(administrator_context, source)
    end

    it 'denies agents' do
      expect(subject).not_to permit(agent_context, source)
    end
  end
end
