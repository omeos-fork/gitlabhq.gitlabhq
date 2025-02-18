# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe QueueBackfillBulkImportFailuresOrganizationId, feature_category: :importers do
  let!(:batched_migration) { described_class::MIGRATION }

  it 'schedules a new batched migration' do
    reversible_migration do |migration|
      migration.before -> {
        expect(batched_migration).not_to have_scheduled_batched_migration
      }

      migration.after -> {
        expect(batched_migration).to have_scheduled_batched_migration(
          table_name: :bulk_import_failures,
          column_name: :id,
          interval: described_class::DELAY_INTERVAL,
          batch_size: described_class::BATCH_SIZE,
          sub_batch_size: described_class::SUB_BATCH_SIZE,
          gitlab_schema: :gitlab_main_cell,
          job_arguments: [
            :organization_id,
            :bulk_import_entities,
            :organization_id,
            :bulk_import_entity_id
          ]
        )
      }
    end
  end
end
