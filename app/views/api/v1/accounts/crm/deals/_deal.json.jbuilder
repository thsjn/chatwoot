json.id resource.id
json.pipeline_id resource.pipeline_id
json.stage_id resource.stage_id
json.title resource.title
json.value_cents resource.value_cents
json.currency resource.currency
json.value resource.value
json.status resource.status
json.expected_close_on resource.expected_close_on
json.closed_at resource.closed_at&.to_i
json.position resource.position
json.stage_entered_at resource.stage_entered_at&.to_i
json.last_activity_at resource.last_activity_at&.to_i
json.next_activity_at resource.next_activity_at&.to_i
json.lock_version resource.lock_version
json.archived_at resource.archived_at&.to_i
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
json.custom_attributes resource.custom_attributes
json.utm resource.utm

json.contact do
  json.id resource.contact.id
  json.name resource.contact.name
  json.email resource.contact.email
  json.phone_number resource.contact.phone_number
  json.thumbnail resource.contact.avatar_url
end

if resource.owner.present?
  json.owner do
    json.id resource.owner.id
    json.name resource.owner.name
    json.available_name resource.owner.available_name
    json.thumbnail resource.owner.avatar_url
  end
end

if resource.team.present?
  json.team do
    json.id resource.team.id
    json.name resource.team.name
  end
end

if resource.source.present?
  json.source do
    json.id resource.source.id
    json.name resource.source.name
    json.kind resource.source.kind
  end
end

# The drawer lists the conversations attached to the deal and highlights the one that
# originated it, so `is_origin` comes from the join row and not from the conversation.
# The list is filtered by `accessible_conversation?`: a conversation of an inbox the agent does not
# belong to must not surface here just because the deal does.
linked_conversations = resource.deal_conversations.select { |link| accessible_conversation?(link.conversation) }

json.conversations linked_conversations do |deal_conversation|
  conversation = deal_conversation.conversation

  json.id conversation.id
  json.display_id conversation.display_id
  json.is_origin deal_conversation.is_origin
  json.status conversation.status

  json.inbox do
    json.id conversation.inbox.id
    json.name conversation.inbox.name
    json.channel_type conversation.inbox.channel_type
  end
end

if resource.lost_reason.present?
  json.lost_reason do
    json.id resource.lost_reason.id
    json.name resource.lost_reason.name
  end
end
