class Crm::IngestConversationJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    Crm::IngestConversationService.new(conversation: conversation).perform
  end
end
