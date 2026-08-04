class CrmListener < BaseListener
  # Only `conversation.created` is handled on purpose. A card stands for the contact's business,
  # not for each message: `message.created` would re-run the ingestion on every inbound message
  # (and the dedupe would just link it to the same deal), while `conversation.resolved`/`updated`
  # do not open a new opportunity. Conversations that arrive before the pipeline is configured are
  # picked up by `Crm::BackfillJob`.
  def conversation_created(event)
    conversation, = extract_conversation_and_account(event)

    # This runs inside the request that created the conversation, so the listener only enqueues:
    # deciding whether the conversation becomes a card takes several queries and belongs in the job.
    Crm::IngestConversationJob.perform_later(conversation)
  end
end
