# Realtime side of a deal. The board is a shared surface — two agents looking at the same funnel
# have to see each other's cards move — so every write to a card publishes an event that
# `ActionCableListener` turns into a websocket push.
#
# The events are dispatched from the model, and not from the controller, so every path that touches
# a card (the API, `Crm::IngestConversationService`, a console fix) reaches the open boards.
module Crm::DealBroadcastable
  extend ActiveSupport::Concern

  # Columns of the realtime card, sliced straight off `attributes` so the payload stays the shape
  # the board already knows from the jbuilder partial.
  CARD_EVENT_ATTRIBUTES = %w[id pipeline_id stage_id title value_cents currency position lock_version
                             expected_close_on custom_attributes utm].freeze
  TIMESTAMP_EVENT_ATTRIBUTES = %w[closed_at stage_entered_at last_activity_at archived_at created_at updated_at].freeze

  included do
    after_create_commit :dispatch_create_event
    after_update_commit :dispatch_update_event
  end

  # Payload of the realtime board events. This is the CARD, not the drawer: the linked
  # conversations are left out because they would cost a query per broadcast and the drawer loads
  # the deal through the API anyway. That is exactly why the store MERGES this into the card it
  # already holds instead of replacing it — a card whose drawer is open keeps its conversations.
  def push_event_data
    attributes.slice(*CARD_EVENT_ATTRIBUTES).symbolize_keys
              .merge(timestamps_event_data)
              .merge(value: value, status: status, next_activity_at: next_activity_at&.to_i)
              .merge(relations_event_data)
  end

  private

  # Epoch seconds, matching what the jbuilder partial serves the board, so a card that arrived
  # through the API and one that arrived through the websocket are the same shape.
  def timestamps_event_data
    attributes.slice(*TIMESTAMP_EVENT_ATTRIBUTES).symbolize_keys.transform_values { |value| value&.to_i }
  end

  # Every relation is published even when empty: the store merges this payload over the card it
  # already holds, so an owner that was just cleared has to arrive as an explicit null.
  def relations_event_data
    {
      contact: contact_event_data,
      owner: owner_event_data,
      team: team && { id: team.id, name: team.name },
      source: source && { id: source.id, name: source.name, kind: source.kind },
      lost_reason: lost_reason && { id: lost_reason.id, name: lost_reason.name }
    }
  end

  def contact_event_data
    { id: contact.id, name: contact.name, email: contact.email, phone_number: contact.phone_number, thumbnail: contact.avatar_url }
  end

  def owner_event_data
    return if owner.blank?

    { id: owner.id, name: owner.name, available_name: owner.available_name, thumbnail: owner.avatar_url }
  end

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(CRM_DEAL_CREATED, Time.zone.now, deal: self)
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(update_event_name, Time.zone.now, deal: self)
  end

  # A single `save` means four different things to the board, and only what actually changed tells
  # them apart: archiving takes the card off the board, a stage/position change is a move (the one
  # event that reconciles two columns), and everything else is a plain edit. Unarchiving reports as
  # an update — the payload carries `archived_at: nil`, which is what puts the card back.
  def update_event_name
    return CRM_DEAL_ARCHIVED if previous_changes.key?('archived_at') && archived?
    return CRM_DEAL_MOVED if previous_changes.keys.intersect?(%w[stage_id position])

    CRM_DEAL_UPDATED
  end
end
