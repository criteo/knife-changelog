# frozen_string_literal: true

require 'git'
require 'spec_helper'

RSpec.describe PolicyChangelog do
  let(:pf_dir) do
    File.expand_path(File.join(File.dirname(__FILE__), '../data'))
  end

  let(:target_dir) do
    File.join(pf_dir, 'updated')
  end

  let(:changelog) do
    PolicyChangelog.new('users', File.join(pf_dir, 'Policyfile.rb'), false)
  end

  let(:lock_current) do
    JSON.parse(File.read(File.join(pf_dir, 'Policyfile.lock.json')))
  end

  let(:lock_target) do
    JSON.parse(File.read(File.join(target_dir, 'Policyfile.lock.json')))
  end

  let(:current_versions) do
    {
      'sudo' => { 'current_version' => '3.5.0' },
      'users' => { 'current_version' => '4.0.0' }
    }
  end

  let(:target_versions) do
    {
      'sudo' => { 'target_version' => '3.5.0' },
      'users' => { 'target_version' => '5.3.1' }
    }
  end

  let(:url) { 'https://supermarket.chef.io/api/v1/cookbooks/users' }

  let(:tags) do
    [
      double(name: '1.0.0'),
      double(name: '0.9.1'),
      double(name: 'v1.0.5'),
      double(name: 'v1.1.1'),
      double(name: 'invalid'),
      double(name: '5.2.1'),
      double(name: 'v0.1.1')
    ]
  end

  before(:each) do
    stub_request(:get, 'https://supermarket.chef.io/api/v1/cookbooks/users').to_return(
      status: 200,
      body: '{
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
    )
  end

  describe '#read_policyfile_lock' do
    context 'when Policyfile.lock.json does not exist' do
      it 'raises an exception' do
        expect { changelog.read_policyfile_lock('/does/not/exist') }.to raise_error(RuntimeError)
      end
    end

    context 'when Policyfile.lock.json is empty' do
      it 'raises an exception' do
        allow(File).to receive(:read).and_return('')
        expect { changelog.read_policyfile_lock('') }.to raise_error(RuntimeError)
      end
    end
  end

  describe '#versions' do
    context 'when type is current' do
      it 'returns correct current versions' do
        expect(changelog.versions(lock_current['cookbook_locks'], 'current')).to eq(current_versions)
      end
    end

    context 'when type is target' do
      it 'returns correct target versions' do
        expect(changelog.versions(lock_target['cookbook_locks'], 'target')).to eq(target_versions)
      end
    end

    context 'when type is not current nor target' do
      it 'raises an exception' do
        expect { changelog.versions(lock_current['cookbook_locks'], 'toto') }.to raise_error(RuntimeError)
      end
    end

    context 'when cookbooks locks are empty or nil' do
      it 'raises an exception' do
        expect { changelog.versions({}, 'current') }.to raise_error(RuntimeError)
        expect { changelog.versions(nil, 'current') }.to raise_error(RuntimeError)
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
    context 'when response not empty' do
      it 'returns valid git repository url' do
        expect(changelog.supermarket_source_url(url)).to match(%r{^(http|https):\/\/.+\.git$})
      end
    end

    context 'when cookbook does not exist' do
      it 'raises an error' do
        response = '{ "error_messages":["Resource does not exist."],"error_code":"NOT_FOUND" }'
        stub_request(:get, url).to_return(status: 404, body: response)
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
        allow(changelog).to receive(:correct_tags)
          .and_return(['v1.0.0', 'v1.0.1'])
        allow(git_repo).to receive_message_chain(:log, :between)
          .with('v1.0.0', 'v1.0.1')
          .and_return([git_commit])

        expect(changelog.git_changelog('https://url.example.git', '1.0.0', '1.0.1'))
          .to eq('e1b971a Add test commit message')
      end
    end
  end

  describe '#git_tag' do
    let(:repo) { double('repo') }

    context 'when tag valid' do
      it 'returns correct git tag' do
        allow(repo).to receive(:checkout).with('1.0.0').and_return(true)

        expect(changelog.git_tag('1.0.0', repo)).to eq('1.0.0')
      end
    end

    context 'when tag invalid and able to correct' do
      it 'returns correct git tag' do
        allow(repo).to receive(:checkout).with('1.0.0').and_raise(::Git::GitExecuteError)
        allow(repo).to receive(:checkout).with('1.0').and_return(true)

        expect(changelog.git_tag('1.0.0', repo)).to eq('1.0')
      end
    end

    context 'when tags invalid and unable to correct' do
      it 'raises exception' do
        allow(repo).to receive(:checkout).with('1.0.0').and_raise(::Git::GitExecuteError)
        allow(repo).to receive(:checkout).with('1.0').and_raise(::Git::GitExecuteError)

        expect { changelog.git_tag('1.0.0', repo) }
          .to raise_error(RuntimeError, 'Difference between Git and Supermarket tags')
      end
    end
  end

  describe '#tag_format' do
    context 'when it receives a tag' do
      let(:repo) { Git::Base }

      it 'detects type for regular tag' do
        allow(repo).to receive_message_chain(:tags, :last, :name).and_return('1.0.0')
        allow(changelog).to receive(:sort_by_version).and_return(repo.tags)
        expect(changelog.tag_format(repo)).to eq('')
      end

      it 'detects type for v-tag' do
        allow(repo).to receive_message_chain(:tags, :last, :name).and_return('v1.0.0')
        allow(changelog).to receive(:sort_by_version).and_return(repo.tags)
        expect(changelog.tag_format(repo)).to eq('v')
      end
    end
  end

  describe '#sort_by_version' do
    context 'when sorting' do
      it 'sorts' do
        expect(changelog.sort_by_version(tags).map(&:name)).to eq(
          %w[invalid v0.1.1 0.9.1 1.0.0 v1.0.5 v1.1.1 5.2.1]
        )
      end
    end
  end

  describe '#reject_version_filter' do
    context 'when current equal to target' do
      it 'returns true' do
        data = { 'current_version' => '1.0.0', 'target_version' => '1.0.0' }
        expect(changelog.reject_version_filter(data)).to be true
      end
    end
    context 'when current not equal to target' do
      it 'returns false' do
        data = { 'current_version' => '1.0.0', 'target_version' => '1.0.1' }
        expect(changelog.reject_version_filter(data)).to be false
      end
    end
    context 'when target does not exist' do
      it 'returns true' do
        expect(changelog.reject_version_filter('current_version' => '1.0.0')).to be true
      end
    end
    context 'when current does not exist but target_does' do
      it 'returns false' do
        expect(changelog.reject_version_filter('target_version' => '1.0.0')).to be false
      end
    end
    context 'when data is nil' do
      it 'raises an exception' do
        expect { changelog.reject_version_filter(nil) }.to raise_error
      end
    end
  end

  describe '#generate_changelog_from_versions' do
    context 'when given origin/target versions' do
      it 'generate the right changelog' do
        expect(changelog).not_to receive(:update_policyfile_lock)

        origin_and_target = {
          'users' => { 'current_version' => '4.0.0', 'target_version' => '5.0.0' },
          'new_cookbook' => { 'target_version' => '8.0.0' }
        }

        allow(changelog).to receive(:git_changelog)
          .with(instance_of(String), '4.0.0', '5.0.0')
          .and_return('e1b971a Add test commit message')

        output = <<~COMMIT.chomp

          Changelog for users: 4.0.0->5.0.0
          ==================================
          e1b971a Add test commit message

          Changelog for new_cookbook: ->8.0.0
          ====================================
          Cookbook was not in the Policyfile.lock.json
        COMMIT

        expect(changelog.generate_changelog_from_versions(origin_and_target)).to eq(output)
      end
    end
  end

  describe '#generate_changelog' do
    context 'when generating a changelog' do
      it 'detects type for regular tag' do
        allow(changelog).to receive(:update_policyfile_lock)
          .and_return(changelog.read_policyfile_lock(target_dir))
        allow(changelog).to receive(:git_changelog)
          .and_return('e1b971a Add test commit message')

        output = "\nChangelog for users: 4.0.0->5.3.1\n" \
          "==================================\n"         \
          'e1b971a Add test commit message'

        expect(changelog.generate_changelog).to eq(output)
      end
    end
  end
end
