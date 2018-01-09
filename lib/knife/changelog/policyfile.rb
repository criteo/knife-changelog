# frozen_string_literal: true

require 'chef/knife'
require 'chef-dk/command/update'
require 'deep_merge'
require 'git'
require 'json'
require 'rest-client'

class PolicyChangelog
  TMP_PREFIX = 'knife-changelog'

  # Initialzes Helper class
  #
  # @param cookbooks [Array<String>] cookbooks to update (@name_args)
  # @param policyfile [String] policyfile path
  def initialize(cookbooks, policyfile)
    @cookbooks_to_update = cookbooks
    @policyfile_path = File.expand_path(policyfile)
    @policyfile_dir = File.dirname(@policyfile_path)
  end

  # Updates the Policyfile.lock to get version differences.
  #
  # @return update_dir [String] tmp directory with updated Policyfile.lock
  def update_policyfile_lock
    update_dir = Dir.mktmpdir
    %w[Policyfile.rb Policyfile.lock.json].each do |file|
      FileUtils.cp(
        File.join(@policyfile_dir, file),
        update_dir
      )
    end
    updater = ChefDK::Command::Update.new
    updater.run([
      File.join(update_dir, 'Policyfile.rb'),
      @cookbooks_to_update
    ].flatten)
    update_dir
  end

  # Parses JSON in Policyfile.lock.
  #
  # @param dir [String] directory containing Policyfile.lock
  # @return [Hash] contents of Policyfile.lock
  def read_policyfile_lock(dir)
    pf_lock = File.join(dir, 'Policyfile.lock.json')
    raise "File #{pf_lock} does not exist" unless File.exist?(pf_lock)
    JSON.parse(File.read(pf_lock))
  end

  # Extracts current or target versions from Policyfile.lock data depending
  # on the type value provided.
  #
  # @param locks [Hash] cookbook data from Policyfile.lock
  # @param type [String] version type - current or target
  # @return [Hash] cookbooks with their versions
  def versions(locks, type)
    raise 'Use "current" or "target" as type' unless %w[current target].include?(type)
    cookbooks = {}
    locks.each do |name, data|
      cookbooks[name] = { "#{type}_version" => data['version'] }
    end
    cookbooks
  end

  # Extracts Git source URL from cookbook 'source_options' data depending
  # on the source type - Supermarket or Git
  #
  # @param s [Hash] source_options for a cookbook in the Policyfile.lock
  # @return [String] Git source code URL
  def get_source_url(s)
    if s.keys.include?('artifactserver')
      { 'source_url' => supermarket_source_url(s['artifactserver'][%r{(.+)\/versions\/.*}, 1]) }
    else
      { 'source_url' => s['git'] }
    end
  end

  # Fetches cookbook metadata from Supermarket and extracts Git source URL
  #
  # @param url [String] Supermarket cookbook URL
  # @return [String] Git source code URL
  def supermarket_source_url(url)
    source_url = JSON.parse(RestClient::Request.execute(
                              url: url,
                              method: :get,
                              verify_ssl: false
    ))['source_url']
    source_url = "#{source_url}.git" unless source_url.end_with?('.git')
    source_url
  end

  # Clones a Git repo in a temporary directory and generates a commit
  # changelog between two version tags
  #
  # @param source_url [String] Git repository URL
  # @param current [String] current cookbook version tag
  # @param target [String] target cookbook version tag
  # @return [String] changelog between tags for one cookbook
  def git_changelog(source_url, current, target)
    dir = Dir.mktmpdir(TMP_PREFIX)
    repo = Git.clone(source_url, dir)
    if tag_format(repo) == 'v'
      repo.log.between("v#{current}", "v#{target}")
    else
      repo.log.between(current, target)
    end.map do |commit|
      "#{commit.sha[0, 7]} #{commit.message.lines.first.strip}"
    end.join("\n")
  end

  # Detects the format of a Git tag - v1.0.0 or 1.0.0
  #
  # @param repo [Git::Base] Git repository object
  # @return [String] Git tag versioning type
  def tag_format(repo)
    repo.tags.last.name[/^v/] ? 'v' : ''
  end

  # Prints out commit changelog in a nicely formatted way
  #
  # @param name [String] cookbook name
  # @param data [Hash] cookbook versions and source url data
  def print_commit_changelog(name, data)
    output = "\nChangelog for #{name}: #{data['current_version']}->#{data['target_version']}"
    puts output
    puts '=' * output.size
    puts git_changelog(data['source_url'], data['current_version'], data['target_version'])
  end

  # Filters out cookbooks which are not updated, are not used after update or
  # are newly added as dependencies during update
  #
  # @param [Hash] cookbook versions and source url data
  # @return [true, false]
  def reject_version_filter(data)
    data['current_version'] == data['target_version'] ||
      data['current_version'].nil? ||
      data['target_version'].nil?
  end

  # Generates Policyfile changelog
  def generate_changelog
    lock_current = read_policyfile_lock(@policyfile_dir)
    current = versions(lock_current['cookbook_locks'], 'current')

    lock_target = read_policyfile_lock(update_policyfile_lock)
    target = versions(lock_target['cookbook_locks'], 'target')

    cookbooks = current.deep_merge(target).reject { |_name, data| reject_version_filter(data) }
    sources = {}
    cookbooks.each_key do |name|
      sources[name] = get_source_url(lock_target['cookbook_locks'][name]['source_options'])
    end
    cookbooks.deep_merge(sources).each { |name, data| print_commit_changelog(name, data) }
  end
end
