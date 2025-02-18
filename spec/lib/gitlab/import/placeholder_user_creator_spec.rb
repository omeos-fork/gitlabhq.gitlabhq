# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Import::PlaceholderUserCreator, feature_category: :importers do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:namespace) { create(:namespace) }

  let(:import_type) { 'github' }
  let(:source_hostname) { 'https://github.com' }
  let(:source_name) { 'Pry Contributor' }
  let(:source_username) { 'a_pry_contributor' }
  let(:source_user_identifier) { '1' }

  let(:source_user) do
    build(:import_source_user,
      import_type: import_type,
      source_hostname: source_hostname,
      source_name: source_name,
      source_username: source_username,
      source_user_identifier: source_user_identifier,
      namespace: namespace
    )
  end

  subject(:service) { described_class.new(source_user) }

  describe '#execute' do
    it 'creates one new placeholder user with a unique email and username' do
      expect { service.execute }.to change { User.where(user_type: :placeholder).count }.from(0).to(1)

      new_placeholder_user = User.where(user_type: :placeholder).last

      expect(new_placeholder_user.name).to eq("Placeholder #{source_name}")
      expect(new_placeholder_user.username).to match(/^aprycontributor_placeholder_[[:alnum:]]+$/)
      expect(new_placeholder_user.email).to match(/^aprycontributor_placeholder_[[:alnum:]]+@noreply.localhost$/)
      expect(new_placeholder_user.namespace.organization).to eq(namespace.organization)
    end

    it_behaves_like 'username and email pair is generated by Gitlab::Utils::UsernameAndEmailGenerator' do
      subject(:result) { service.execute }

      let(:username_prefix) { 'aprycontributor_placeholder' }
      let(:email_domain) { 'noreply.localhost' }
    end

    it 'does not cache user policies', :request_store do
      expect { service.execute }.not_to change {
                                          Gitlab::SafeRequestStore.storage.keys.select do |key|
                                            key.to_s.include?('User')
                                          end
                                        }
    end

    it 'logs placeholder user creation' do
      allow(::Import::Framework::Logger).to receive(:info)

      service.execute

      expect(::Import::Framework::Logger).to have_received(:info).with(
        hash_including(
          message: 'Placeholder user created',
          source_user_id: source_user.id,
          import_type: source_user.import_type,
          namespace_id: source_user.namespace_id,
          user_id: User.last.id
        )
      )
    end

    context 'when there are non-unique usernames on the same import source' do
      it 'creates two unique users with different usernames and emails' do
        placeholder_user1 = described_class.new(source_user).execute
        placeholder_user2 = described_class.new(source_user).execute

        expect(placeholder_user1.username).not_to eq(placeholder_user2.username)
        expect(placeholder_user1.email).not_to eq(placeholder_user2.email)
      end
    end

    context 'when source_name is nil' do
      let(:source_name) { nil }

      it 'assigns a default name' do
        placeholder_user = service.execute

        expect(placeholder_user.name).to eq("Placeholder #{import_type} Source User")
      end
    end

    context 'when source_username is nil' do
      let(:source_username) { nil }

      it 'generates a fallback username and email, and default name' do
        placeholder_user = service.execute

        expect(placeholder_user.username).to match(/^#{import_type}_placeholder_[[:alnum:]]+$/)
        expect(placeholder_user.email).to match(/^#{import_type}_placeholder_[[:alnum:]]+@noreply.localhost$/)
      end
    end

    context 'when the incoming source_user attributes are invalid' do
      context 'when source_name is too long' do
        let(:source_name) { 'a' * 500 }

        it 'truncates the source name to 127 characters' do
          placeholder_user = service.execute

          expect(placeholder_user.first_name).to eq('Placeholder')
          expect(placeholder_user.last_name).to eq('a' * 127)
        end
      end

      context 'when the source_username contains invalid characters' do
        where(:input_username, :expected_output) do
          '.asdf'     | /^asdf_placeholder_[[:alnum:]]+$/
          'asdf^ghjk' | /^asdfghjk_placeholder_[[:alnum:]]+$/
          '.'         | /^#{import_type}_placeholder_[[:alnum:]]+$/
        end

        with_them do
          let(:source_username) { input_username }

          it do
            placeholder_user = service.execute

            expect(placeholder_user.username).to match(expected_output)
          end
        end
      end

      context 'when source_username is too long' do
        let(:source_username) { 'a' * 500 }

        it 'truncates the original username to 200 characters' do
          placeholder_user = service.execute

          expect(placeholder_user.username).to match(/^#{'a' * 200}_placeholder_[[:alnum:]]+$/)
        end
      end
    end
  end

  describe '.placeholder_email?' do
    it "matches the emails created for placeholder users" do
      import_source_user = create(:import_source_user)
      placeholder_user = described_class.new(import_source_user).execute

      expect(described_class.placeholder_email?(placeholder_user.email)).to eq(true)
    end

    it "matches the emails created for placeholders users when source username and name are missing" do
      import_source_user = create(:import_source_user, source_username: nil, source_name: nil)
      placeholder_user = described_class.new(import_source_user).execute

      expect(described_class.placeholder_email?(placeholder_user.email)).to eq(true)
    end

    where(:email, :expected_match) do
      'foo_placeholder_Az1@noreply.localhost' | true
      'foo_placeholder_Az$1@noreply.localhost' | false
      'placeholder_Az1@noreply.localhost' | false
      'foo_placeholder@noreply.localhost' | false
    end

    with_them do
      specify do
        expect(described_class.placeholder_email?(email)).to eq(expected_match)
      end
    end

    context 'with legacy placeholder user email formats' do
      where(:import_type) { Import::HasImportSource::IMPORT_SOURCES.except(:none).keys }

      with_them do
        it "matches the legacy emails format for placeholder users" do
          email = "#{import_type}_5c34ae6b9_1@#{Settings.gitlab.host}"
          expect(described_class.placeholder_email?(email)).to eq(true)
        end
      end
    end
  end
end
