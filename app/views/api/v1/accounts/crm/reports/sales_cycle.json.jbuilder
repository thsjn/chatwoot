json.payload do
  @sales_cycle.each do |status, row|
    json.set! status do
      # Seconds between the creation of the deal and its closing; null when nothing closed yet.
      json.avg_cycle_seconds row[:avg_cycle_seconds]
      json.deals_count row[:deals_count]
    end
  end
end
