# frozen_string_literal: true

require 'git'
require 'spec_helper'

RSpec.describe PolicyChangelog do
  let(:pf_dir) do
    File.join(File.dirname(__FILE__), '../data')
  end

  let(:changelog) do
    PolicyChangelog.new('users', File.join(pf_dir, 'Policyfile.rb'))
  end

  describe '#versions' do
    context 'when type is current' do
      it 'returns correct current versions' do
        locks = JSON.parse(File.read(File.join(pf_dir, 'pf_lock_current.json')))['cookbook_locks']
        current_versions = {
          'sudo' => { 'current_version' => '3.5.0' },
          'users' => { 'current_version' => '4.0.0' }
        }
        expect(changelog.versions(locks, 'current')).to eq(current_versions)
      end
    end

    context 'when type is target' do
      it 'returns correct target versions' do
        locks = JSON.parse(File.read(File.join(pf_dir, 'pf_lock_target.json')))['cookbook_locks']
        target_versions = {
          'sudo' => { 'target_version' => '3.5.0' },
          'users' => { 'target_version' => '5.3.1' }
        }
        expect(changelog.versions(locks, 'target')).to eq(target_versions)
      end
    end

    context 'when type is not current nor target' do
      it 'raises and exception' do
        expect { changelog.versions(nil, 'toto') }.to raise_error(RuntimeError)
      end
    end
  end

  describe '#get_source_url' do
    context 'when extracting source url' do
      it 'returns an http url for supermarket' do
        supermarket_source = { 'artifactserver' => 'https://url.example/cookbook/name/versions/3.5.0/download' }
        allow(changelog).to receive(:supermarket_source_url).and_return('https://url.example')
        expect(changelog.get_source_url(supermarket_source)['source_url'])
          .to match(%r{^(http|https):\/\/.+$})
      end

      it 'raises exception for invalid supermarket url' do
        bad_supermarket_source = { 'artifactserver' => 'https://url.example' }
        expect { changelog.get_source_url(bad_supermarket_source)['source_url'] }
          .to raise_error(ArgumentError)
      end

      it 'returns a git repo url for git' do
        git_source = { 'git' => 'https://url.example.git' }
        expect(changelog.get_source_url(git_source)['source_url'])
          .to match(%r{^(http|https):\/\/.+\.git$})
      end
    end
  end

  describe '#supermarket_source_url' do
    let(:url) { 'https://supermarket.chef.io/api/v1/cookbooks/users' }

    context 'when response not empty' do
      it 'returns valid git repository url' do
        supermarket_response = '{
          "name": "users",
          "maintainer": "chef",
          "description": "Creates users from a databag search",
          "category": "Other",
          "latest_version": "https://supermarket.chef.io/api/v1/cookbooks/users/versions/5.3.1",
          "external_url": "https://github.com/chef-cookbooks/users",
          "source_url": "https://github.com/chef-cookbooks/users",
          "issues_url": "https://github.com/chef-cookbooks/users/issues",
          "average_rating": null,
          "created_at": "2010-07-27T05:34:01.000Z",
          "updated_at": "2017-12-15T18:08:26.990Z",
          "up_for_adoption": null,
          "deprecated": false,
          "versions": [],
          "metrics": {}
        }'
        stub_request(:get, url).to_return(status: 200, body: supermarket_response)
        expect(changelog.supermarket_source_url(url)).to match(%r{^(http|https):\/\/.+\.git$})
      end
    end

    context 'when cookbook does not exist' do
      it 'raises an error' do
        supermarket_response = '{ "error_messages":["Resource does not exist."],"error_code":"NOT_FOUND" }'
        stub_request(:get, url).to_return(status: 404, body: supermarket_response)
        expect { changelog.supermarket_source_url(url) }.to raise_error(RestClient::NotFound)
      end
    end
  end

  describe '#git_changelog' do
    let(:git) { Git }

    let(:git_repo) { double(Git::Base.new) }

    let(:git_commit) do
      double(
        sha: 'e1b971a32f3a582766e4f62022ef7ed88e5eb8ba',
        message: "Add test commit message\nThis line should not be shown"
      )
    end

    context 'when given two tags' do
      it 'generates a changelog between two tags' do
        allow(changelog).to receive(:tag_format).and_return('v')
        allow(git).to receive(:clone).and_return(git_repo)
        allow(git_repo).to receive_message_chain(:log, :between)
          .with('v1.0.0', 'v1.0.1')
          .and_return([git_commit])

        expect(changelog.git_changelog('https://url.example.git', '1.0.0', '1.0.1'))
          .to eq('e1b971a Add test commit message')
      end
    end
  end

  describe '#tag_format' do
    context 'when it receives a tag' do
      let(:repo) { Git::Base }

      it 'detects type for regular tag' do
        allow(repo).to receive_message_chain(:tags, :last, :name).and_return('1.0.0')
        expect(changelog.tag_format(repo)).to eq('')
      end

      it 'detects type for v-tag' do
        allow(repo).to receive_message_chain(:tags, :last, :name).and_return('v1.0.0')
        expect(changelog.tag_format(repo)).to eq('v')
      end
    end
  end
end
