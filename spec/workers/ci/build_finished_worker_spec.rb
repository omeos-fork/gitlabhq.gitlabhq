# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::BuildFinishedWorker, feature_category: :continuous_integration do
  include AfterNextHelpers

  subject { described_class.new.perform(build.id) }

  describe '#perform' do
    context 'when build exists' do
      let_it_be(:build) do
        create(:ci_build, :success, user: create(:user), pipeline: create(:ci_pipeline))
      end

      before do
        expect(Ci::Build).to receive(:find_by).with({ id: build.id }).and_return(build)
      end

      it 'calculates coverage and calls hooks', :aggregate_failures do
        expect(build).to receive(:update_coverage).ordered

        expect_next(Ci::BuildReportResultService).to receive(:execute).with(build)

        expect(build).to receive(:execute_hooks)
        expect(ChatNotificationWorker).not_to receive(:perform_async)
        expect(Ci::ArchiveTraceWorker).to receive(:perform_in)

        subject
      end

      context 'when build is failed' do
        before do
          build.update!(status: :failed)
        end

        it 'adds a todo' do
          expect(::Ci::MergeRequests::AddTodoWhenBuildFailsWorker).to receive(:perform_async)

          subject
        end

        context 'when auto_cancel_on_job_failure is set to an invalid value' do
          before do
            allow(build.pipeline)
              .to receive(:auto_cancel_on_job_failure)
              .and_return('invalid value')
          end

          it 'raises an exception' do
            expect { subject }.to raise_error(
              ArgumentError, 'Unknown auto_cancel_on_job_failure value: invalid value')
          end

          context 'when auto_cancel_pipeline_on_job_failure feature flag is disabled' do
            before do
              stub_feature_flags(auto_cancel_pipeline_on_job_failure: false)
            end

            it 'does not raise an exception' do
              expect { subject }.not_to raise_error
            end
          end
        end

        context 'when auto_cancel_on_job_failure is set to all' do
          before do
            build.pipeline.create_pipeline_metadata!(
              project: build.pipeline.project, auto_cancel_on_job_failure: 'all'
            )
          end

          it 'cancels the pipeline' do
            expect(::Ci::UserCancelPipelineWorker).to receive(:perform_async)
              .with(build.pipeline.id, build.pipeline.id, build.user.id)

            subject
          end

          context 'when auto_cancel_pipeline_on_job_failure feature flag is disabled' do
            before do
              stub_feature_flags(auto_cancel_pipeline_on_job_failure: false)
            end

            it 'does not cancel the pipeline' do
              expect(::Ci::UserCancelPipelineWorker).not_to receive(:perform_async)

              subject
            end
          end
        end

        context 'when auto_cancel_on_job_failure is set to none' do
          before do
            build.pipeline.create_pipeline_metadata!(
              project: build.pipeline.project, auto_cancel_on_job_failure: 'none'
            )
          end

          it 'does not cancel the pipeline' do
            expect(::Ci::UserCancelPipelineWorker).not_to receive(:perform_async)

            subject
          end

          context 'when auto_cancel_pipeline_on_job_failure feature flag is disabled' do
            before do
              stub_feature_flags(auto_cancel_pipeline_on_job_failure: false)
            end

            it 'does not cancel the pipeline' do
              expect(::Ci::UserCancelPipelineWorker).not_to receive(:perform_async)

              subject
            end
          end
        end

        context 'when a build can be auto-retried' do
          before do
            allow(build)
              .to receive(:auto_retry_allowed?)
              .and_return(true)
          end

          it 'does not add a todo' do
            expect(::Ci::MergeRequests::AddTodoWhenBuildFailsWorker)
              .not_to receive(:perform_async)

            subject
          end

          context 'when auto_cancel_on_job_failure is set to all' do
            before do
              build.pipeline.create_pipeline_metadata!(
                project: build.pipeline.project, auto_cancel_on_job_failure: 'all'
              )
            end

            it 'does not cancel the pipeline' do
              expect(::Ci::UserCancelPipelineWorker).not_to receive(:perform_async)

              subject
            end
          end
        end
      end

      context 'when build has a chat' do
        before do
          build.pipeline.update!(source: :chat)
        end

        it 'schedules a ChatNotification job' do
          expect(ChatNotificationWorker).to receive(:perform_async).with(build.id)

          subject
        end
      end

      context 'when it has a token' do
        it 'removes the token' do
          expect { subject }.to change { build.reload.token }.to(nil)
        end
      end
    end

    context 'when build does not exist' do
      it 'does not raise exception' do
        expect { described_class.new.perform(non_existing_record_id) }
          .not_to raise_error
      end
    end
  end
end
