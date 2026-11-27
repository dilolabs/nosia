# Recovers unfinished Notes imports and removes terminal staging.
class NoteImport::ReconcileJob < ApplicationJob
  queue_as :default

  # @return [void]
  def perform
    NoteImport.reconcile_now
  end
end
