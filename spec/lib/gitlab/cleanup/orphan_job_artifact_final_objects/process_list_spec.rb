# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Cleanup::OrphanJobArtifactFinalObjects::ProcessList, :orphan_final_artifacts_cleanup, :clean_gitlab_redis_shared_state, feature_category: :build_artifacts do
  describe '#run!' do
    let(:processor) do
      described_class.new(
        force_restart: force_restart,
        filename: orphan_list_filename
      )
    end

    let(:orphan_list_filename) { 'orphan_objects.csv' }
    let(:deleted_list_filename) { "#{described_class::DELETED_LIST_FILENAME_PREFIX}#{orphan_list_filename}" }
    let(:force_restart) { false }
    let(:remote_directory) { 'artifacts' }
    let(:bucket_prefix) { nil }

    let(:fog_connection) do
      stub_object_storage_uploader(
        config: Gitlab.config.artifacts.object_store,
        uploader: JobArtifactUploader,
        direct_upload: true
      )
    end

    let(:orphan_final_object_1) { create_fog_file }
    let(:orphan_final_object_2) { create_fog_file }
    let(:orphan_final_object_3) { create_fog_file }
    let(:orphan_final_object_4) { create_fog_file }

    let(:non_orphan_final_object) do
      create_fog_file.tap do |file|
        create(:ci_job_artifact, file_final_path: path_without_bucket_prefix(file.key))
      end
    end

    before do
      stub_const("#{described_class}::BATCH_SIZE", 2)

      Gitlab.config.artifacts.object_store.tap do |config|
        config[:remote_directory] = remote_directory
        config[:bucket_prefix] = bucket_prefix
      end

      allow(Gitlab::AppLogger).to receive(:info)

      File.open(orphan_list_filename, 'a') do |file|
        file.puts([orphan_final_object_1.key, orphan_final_object_1.content_length].join(','))
        file.puts([orphan_final_object_2.key, orphan_final_object_2.content_length].join(','))
        file.puts([non_orphan_final_object.key, non_orphan_final_object.content_length].join(','))
        file.puts([orphan_final_object_3.key, orphan_final_object_3.content_length].join(','))
        file.puts([orphan_final_object_4.key, orphan_final_object_4.content_length].join(','))
      end
    end

    after do
      File.delete(orphan_list_filename) if File.file?(orphan_list_filename)
      File.delete(deleted_list_filename) if File.file?(deleted_list_filename)
    end

    subject(:run) { processor.run! }

    shared_examples_for 'deleting orphan final job artifact objects' do
      it 'deletes all objects without a matching DB record from the given CSV file and logs them to the deleted list' do
        run

        expect_processing_list_log_message(orphan_list_filename)
        expect_deleted_object_log_message(orphan_final_object_1)
        expect_deleted_object_log_message(orphan_final_object_2)
        expect_deleted_object_log_message(orphan_final_object_3)
        expect_deleted_object_log_message(orphan_final_object_4)
        expect_skipping_object_with_job_artifact_record_log_message(non_orphan_final_object)
        expect_done_deleting_log_message(deleted_list_filename)

        expect_deleted_list_to_contain_exactly(deleted_list_filename, [
          orphan_final_object_1,
          orphan_final_object_2,
          orphan_final_object_3,
          orphan_final_object_4
        ])

        expect_object_to_be_deleted(orphan_final_object_1)
        expect_object_to_be_deleted(orphan_final_object_2)
        expect_object_to_be_deleted(orphan_final_object_3)
        expect_object_to_be_deleted(orphan_final_object_4)
        expect_object_to_exist(non_orphan_final_object)
      end

      context 'when given custom filename is under a directory' do
        let(:orphan_list_filename) { 'spec/fixtures/custom.csv' }
        let(:deleted_list_filename) { "spec/fixtures/#{described_class::DELETED_LIST_FILENAME_PREFIX}custom.csv" }

        it 'correctly generates the deleted list file under the same directory as the orphans list' do
          run

          expect_deleted_list_to_contain_exactly(deleted_list_filename, [
            orphan_final_object_1,
            orphan_final_object_2,
            orphan_final_object_3,
            orphan_final_object_4
          ])
        end
      end

      context 'when an object listed in the CSV file does not exist in storage anymore' do
        before do
          orphan_final_object_1.destroy # rubocop:disable Rails/SaveBang -- not the AR method

          allow_next_instance_of(Fog::AWS::Storage::File) do |instance|
            allow(instance).to receive(:destroy).and_wrap_original do |m, *args|
              result = m.call(*args)

              if instance.key == orphan_final_object_1.key
                destroy_return_value
              else
                result
              end
            end
          end

          run
        end

        context 'and the destroy method returns false which is the case for GCP' do
          let(:destroy_return_value) { false }

          it 'does not fail but does not log the non-existent path to the deleted list' do
            expect_no_deleted_object_log_message(orphan_final_object_1)
            expect_deleted_object_log_message(orphan_final_object_2)
            expect_deleted_object_log_message(orphan_final_object_3)
            expect_deleted_object_log_message(orphan_final_object_4)

            expect_deleted_list_to_contain_exactly(deleted_list_filename, [
              orphan_final_object_2,
              orphan_final_object_3,
              orphan_final_object_4
            ])
          end
        end

        context 'and the destroy method returns true regardless which is the case for S3 and Azure' do
          let(:destroy_return_value) { true }

          it 'does not fail and still logs the non-existent path to the deleted list' do
            expect_deleted_object_log_message(orphan_final_object_1)
            expect_deleted_object_log_message(orphan_final_object_2)
            expect_deleted_object_log_message(orphan_final_object_3)
            expect_deleted_object_log_message(orphan_final_object_4)

            expect_deleted_list_to_contain_exactly(deleted_list_filename, [
              orphan_final_object_1,
              orphan_final_object_2,
              orphan_final_object_3,
              orphan_final_object_4
            ])
          end
        end
      end

      context 'when interrupted in the middle of processing entries' do
        let(:dummy_error) { Class.new(StandardError) }

        before do
          loop_counter = 0

          allow(processor).to receive(:orphans_from_batch).and_wrap_original do |m, *args|
            raise dummy_error if loop_counter == 1

            loop_counter += 1
            m.call(*args)
          end
        end

        it 'resumes from last known cursor position on the next run' do
          expect { processor.run! }.to raise_error(dummy_error)

          # we have a batch size of 2 here, so we expect only the first 2 lines
          # from the CSV has been processed before it got interrupted
          expect_deleted_object_log_message(orphan_final_object_1)
          expect_object_to_be_deleted(orphan_final_object_1)
          expect_deleted_object_log_message(orphan_final_object_2)
          expect_object_to_be_deleted(orphan_final_object_2)
          expect_object_to_exist(orphan_final_object_3)
          expect_object_to_exist(orphan_final_object_4)

          expect_deleted_list_to_contain_exactly(deleted_list_filename, [
            orphan_final_object_1,
            orphan_final_object_2
          ])

          saved_cursor_position = fetch_saved_cursor_position

          new_processor = described_class.new(
            force_restart: false,
            filename: orphan_list_filename
          )

          new_processor.run!

          expect_resuming_from_cursor_position_log_message(saved_cursor_position)
          expect_deleted_object_log_message(orphan_final_object_3)
          expect_deleted_object_log_message(orphan_final_object_4)
          expect_skipping_object_with_job_artifact_record_log_message(non_orphan_final_object)

          expect_object_to_be_deleted(orphan_final_object_3)
          expect_object_to_be_deleted(orphan_final_object_4)
          expect_object_to_exist(non_orphan_final_object)

          expect_deleted_list_to_contain_exactly(deleted_list_filename, [
            orphan_final_object_1,
            orphan_final_object_2,
            orphan_final_object_3,
            orphan_final_object_4
          ])
        end

        context 'and force_restart is true' do
          it 'starts from the first page on the next run' do
            expect { processor.run! }.to raise_error(dummy_error)

            expect_deleted_list_to_contain_exactly(deleted_list_filename, [
              orphan_final_object_1,
              orphan_final_object_2
            ])

            new_processor = described_class.new(
              force_restart: true,
              filename: orphan_list_filename
            )

            new_processor.run!

            expect_no_resuming_from_marker_log_message
            expect_deleted_object_log_message(orphan_final_object_1, times: 2)
            expect_deleted_object_log_message(orphan_final_object_2, times: 2)
            expect_deleted_object_log_message(orphan_final_object_3)
            expect_deleted_object_log_message(orphan_final_object_4)

            expect_deleted_list_to_contain_exactly(deleted_list_filename, [
              orphan_final_object_1,
              orphan_final_object_2,
              orphan_final_object_3,
              orphan_final_object_4
            ])
          end
        end
      end
    end

    context 'when not configured to use bucket_prefix' do
      let(:remote_directory) { 'artifacts' }
      let(:bucket_prefix) { nil }

      it_behaves_like 'deleting orphan final job artifact objects'
    end

    context 'when configured to use bucket_prefix' do
      let(:remote_directory) { 'main-bucket' }
      let(:bucket_prefix) { 'my/artifacts' }

      it_behaves_like 'deleting orphan final job artifact objects'
    end
  end
end
