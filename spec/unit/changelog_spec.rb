# frozen_string_literal: true

require_relative '../spec_helper'
require 'webmock/rspec'
require 'berkshelf'

WebMock.disable_net_connect!

RSpec.shared_examples 'changelog generation' do
  # this supposes that "changelog" is an instance of KnifeChangelog::Changelog
  it 'detects basic changelog' do
    mock_git('second_out_of_date', <<-EOH)
        aaaaaa commit in second_out_of_date
        bbbbbb bugfix in second_out_of_date
    EOH
    mock_git('outdated1', <<-EOH)
        aaaaaa commit in outdated1
        bbbbbb bugfix in outdated1
    EOH
    mock_git('uptodate', '')

    changelog_txt = changelog.run(%w[new_cookbook uptodate outdated1 second_out_of_date])
    expect(changelog_txt).to match(/commit in outdated1/)
    expect(changelog_txt).to match(/commit in second_out_of_date/)
    expect(changelog_txt).not_to match(/uptodate/)
    expect(changelog_txt).to match(/new_cookbook: \n.*\nCookbook was not/)
  end
end

describe KnifeChangelog::Changelog do
  before(:each) do
    stub_request(:get, %r{https://mysupermarket.io/api/v1/cookbooks/})
      .to_return(status: 404, body: '{}')

    mock_supermarket('uptodate', %w[1.0.0])
    mock_supermarket('outdated1', %w[1.0.0 1.1.0])
    # TODO: we should make second_out_of_date a git location
    mock_supermarket('second_out_of_date', %w[1.0.0 1.2.0])

    mock_universe('https://mysupermarket2.io', uptodate: %w[1.0.0], outdated1: %w[1.0.0 1.1.0], second_out_of_date: %w[1.0.0 1.2.0])
    mock_universe('https://mysupermarket.io', {})
  end

  def mock_git(name, changelog)
    expect(KnifeChangelog::Git).to receive(:new)
      .with(anything, /#{name}(.git|$)/)
      .and_return(double(name,
    shallow_clone: '/tmp/randomdir12345',
    revision_exists?: true,
    files: [],
    log: changelog.split("\n")))
  end

  def mock_supermarket(name, versions)
    stub_request(:get, %r{https://mysupermarket2.io/api/v1/cookbooks/#{name}})
      .to_return(status: 200, body: supermarket_versions(name, versions))
  end

  def supermarket_versions(name, versions)
    {
      name: name,
      maintainer: 'Linus',
      description: 'small project on the side',
      category: 'Operating System',
      source_url: "https://github.com/chef-cookbooks/#{name}",
      versions: []
    }.tap do |json|
      versions.each do |v|
        json[:versions] << "https://source.io/#{name}/#{v}"
      end
    end.to_json
  end

  def mock_universe(supermarket_url, cookbooks)
    universe = cookbooks.transform_values do |versions|
      versions.map do |v|
        [v, {
          location_type: 'opscode',
          location_path: "#{supermarket_url}/api/v1",
          download_url: "#{supermarket_url}/api/v1/cookbooks/insertnamehere/versions/#{v}/download",
          dependencies: {}
        }]
      end.to_h
    end
    stub_request(:get, "#{supermarket_url}/universe")
      .to_return(status: 200, body: universe.to_json)
  end

  context 'in Berksfile mode' do
    let(:berksfile) do
      Berkshelf::Berksfile.from_options(
        berksfile: File.join(File.dirname(__FILE__), '../data/Berksfile')
      )
    end

    let(:options) do
      {}
    end

    let(:changelog) do
      KnifeChangelog::Changelog::Berksfile.new(berksfile, options)
    end

    include_examples 'changelog generation'

    context 'with --update' do
      let(:options) do
        { update: true }
      end
      it 'updates Berksfile' do
        mock_git('outdated1', <<-EOH)
          aaaaaa commit in outdated1
          bbbbbb bugfix in outdated1
        EOH
        expect(berksfile).to receive(:update).with('outdated1')
        changelog.run(%w[outdated1])
      end
    end
  end

  context 'in policyfile mode' do
    let(:policyfile_path) { File.join(File.dirname(__FILE__), '../data/Policyfile.rb') }

    let(:options) do
      {}
    end

    let(:changelog) do
      KnifeChangelog::Changelog::Policyfile.new(policyfile_path, options)
    end

    before(:each) do
      allow(changelog.policy).to receive(:cache_fixed_version_cookbooks)
    end

    include_examples 'changelog generation'

    context 'with --update' do
      let(:options) do
        { update: true }
      end
      it 'fails with not implemented error' do
        mock_git('outdated1', <<-EOH)
          aaaaaa commit in outdated1
          bbbbbb bugfix in outdated1
        EOH
        expect { changelog.run(%w[outdated1]) }.to raise_error(NotImplementedError)
      end
    end

    context 'whith --allow-update-all ' do
      let(:options) do
        { "allow_update_all": true }
      end

      it 'should compute the changelog of all dependencies' do
        mock_git('second_out_of_date', <<-EOH)
            aaaaaa commit in second_out_of_date
            bbbbbb bugfix in second_out_of_date
        EOH
        mock_git('outdated1', <<-EOH)
            aaaaaa commit in outdated1
            bbbbbb bugfix in outdated1
        EOH
        mock_git('uptodate', '')

        expect(changelog).to receive(:supermarkets_for).with('outdated1')
          .and_return(["https://mysupermarket2.io"])
        expect(changelog).to receive(:supermarkets_for).with('second_out_of_date')
          .and_return(["https://mysupermarket2.io"])
        expect(changelog).to receive(:supermarkets_for).with('uptodate')
          .and_return(["https://mysupermarket2.io"])
        changelog.run([])
      end
    end
  end
end

class Hash
  unless Chef::Version.new(RUBY_VERSION) >= Chef::Version.new('2.4')
    def transform_values
      map { |k, v| [k, (yield v)] }.to_h
    end
  end
end
