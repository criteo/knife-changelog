# frozen_string_literal: true

require_relative '../spec_helper'
require 'webmock/rspec'
require 'berkshelf'

WebMock.disable_net_connect!

describe KnifeChangelog::Changelog do
  before(:each) do
    stub_request(:get, %r{https://mysupermarket.io/api/v1/cookbooks/})
      .to_return(status: 404, body: '{}')

    mock_supermarket('uptodate', %w[1.0.0])
    mock_supermarket('outdated1', %w[1.0.0 1.1.0])
    mock_supermarket('second_out_of_date', %w[1.0.0 1.2.0])

    mock_git('second_out_of_date', <<~EOH)
        aaaaaa commit in second_out_of_date
        bbbbbb bugfix in second_out_of_date
    EOH
    mock_git('outdated1', <<~EOH)
        aaaaaa commit in outdated1
        bbbbbb bugfix in outdated1
    EOH
    mock_git('uptodate', '')
  end

  def mock_git(name, changelog)
    expect(KnifeChangelog::Git).to receive(:new)
      .with(anything, /#{name}.git/)
      .and_return(double(name,
    shallow_clone: true,
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

  context 'in Berksfile mode' do
    let(:berksfile) do
      Berkshelf::Berksfile.from_options(
        berksfile: File.join(File.dirname(__FILE__), '../data/Berksfile')
      )
    end

    let(:changelog) do
      KnifeChangelog::Changelog.new(berksfile.lockfile.locks, {}, berksfile.sources)
    end

    it 'detects basic changelog' do
      changelog_txt = changelog.run(%w[uptodate outdated1 second_out_of_date])
      expect(changelog_txt).to match(/commit in outdated1/)
      expect(changelog_txt).to match(/commit in second_out_of_date/)
      expect(changelog_txt).not_to match(/uptodate/)
    end
  end

  context 'in policyfile mode' do
  end
end
