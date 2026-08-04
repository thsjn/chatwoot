require 'rails_helper'

describe CrmListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:event) { Events::Base.new('conversation.created', Time.zone.now, conversation: conversation) }

  describe '#conversation_created' do
    it 'enqueues the ingestion job for the conversation' do
      expect { listener.conversation_created(event) }
        .to have_enqueued_job(Crm::IngestConversationJob).with(conversation)
    end

    it 'does not create any deal by itself' do
      expect { listener.conversation_created(event) }.not_to change(Crm::Deal, :count)
    end
  end
end
