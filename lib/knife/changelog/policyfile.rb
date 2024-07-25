# frozen_string_literal: true

require 'chef/knife'
require 'chef-cli/command/update'
require 'chef-cli/command/install'
require 'deep_merge'
require 'git'
require 'json'
require 'rest-client'

class PolicyChangelog
  TMP_PREFIX = 'knife-changelog'
  # Regex matching Chef cookbook version syntax
  # See https://docs.chef.io/cookbook_versioning.html#syntax
  VERSION_REGEX = /^[1-9]*[0-9](\.[0-9]+){1,2}$/

  # Initialzes Helper class
  #
  # @param cookbooks [Array<String>] cookbooks to update (@name_args)
  # @param policyfile [String] policyfile path
  def initialize(cookbooks, policyfile, with_dependencies)
    @cookbooks_to_update = cookbooks
    @policyfile_path = File.expand_path(policyfile)
    @policyfile_dir = File.dirname(@policyfile_path)
    @with_dependencies = with_dependencies
  end

  # Updates the Policyfile.lock to get version differences.
  #
  # @return update_dir [String] tmp directory with updated Policyfile.lock
  def update_policyfile_lock
    backup_dir = Dir.mktmpdir
    FileUtils.cp(File.join(@policyfile_dir, 'Policyfile.lock.json'), backup_dir)
    installer = ChefCLI::Command::Install.new
    raise "Cannot install Policyfile lock #{@policyfile_path}" unless installer.run([@policyfile_relative_path]).zero?
    updater = ChefCLI::Command::Update.new
    raise "Error updating Policyfile lock #{@policyfile_path}" unless updater.run([@policyfile_path, @cookbooks_to_update].flatten).zero?
    updated_policyfile_lock = read_policyfile_lock(@policyfile_dir)
    FileUtils.cp(File.join(backup_dir, 'Policyfile.lock.json'), @policyfile_dir)
    updated_policyfile_lock
  end

  # Parses JSON in Policyfile.lock.
  #
  # @param dir [String] directory containing Policyfile.lock
  # @return [Hash] contents of Policyfile.lock
  def read_policyfile_lock(dir)
    lock = File.join(dir, 'Policyfile.lock.json')
    raise "File #{lock} does not exist" unless File.exist?(lock)
    content = JSON.parse(File.read(lock))
    raise 'Policyfile.lock empty' if content.empty?
    content
  end

  # Extracts current or target versions from Policyfile.lock data depending
  # on the type value provided.
  #
  # @param locks [Hash] cookbook data from Policyfile.lock
  # @param type [String] version type - current or target
  # @return [Hash] cookbooks with their versions
  def versions(locks, type)
    raise 'Use "current" or "target" as type' unless %w[current target].include?(type)
    raise 'Cookbook locks empty or nil' if locks.nil? || locks.empty?
    cookbooks = {}
    locks.each do |name, data|
      cookbooks[name] = if data['source_options'].keys.include?('git')
                          { "#{type}_version" => data['source_options']['revision'] }
                        else
                          { "#{type}_version" => data['version'] }
                        end
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
  def git_changelog(source_url, current, target, cookbook = nil)
    dir = Dir.mktmpdir(TMP_PREFIX)
    repo = Git.clone(source_url, dir)
    cookbook_path = cookbook ? git_cookbook_path(repo, cookbook) : '.'
    repo.log.path(cookbook_path).between(git_ref(current, repo, cookbook), git_ref(target, repo, cookbook)).map do |commit|
      "#{commit.sha[0, 7]} #{commit.message.lines.first.strip}"
    end.join("\n")
  end

  # Tries to find the location of a specific cookbook in the given repo
  #
  # @param repo [Git::Base] Git repository object
  # @param cookbook [String] name of the cookbook to search the location
  # @return [String] reative location of the cookbook in the repo
  def git_cookbook_path(repo, cookbook)
    metadata_files = ['metadata.rb', '*/metadata.rb'].flat_map { |location| repo.ls_files(location).keys }
    metadata_path = metadata_files.find do |path|
      path = ::File.join(repo.dir.to_s, path)
      ::Chef::Cookbook::Metadata.new.tap { |m| m.from_file(path) }.name == cookbook
    end
    raise "Impossible to find matching metadata for #{cookbook} in #{repo.remote.url}" unless metadata_path
    ::File.dirname(metadata_path)
  end

  # Tries to convert a supermarket tag to a git reference
  # if there is a difference in formatting between the two.
  # This is issue is present for the 'java' cookbook.
  # https://github.com/agileorbit-cookbooks/java/issues/450
  #
  # @param ref [String] version reference
  # @param repo [Git::Base] Git repository object
  # @param cookbook [String] name of the cookbook to ref against
  # @return [String]
  def git_ref(myref, repo, cookbook_name = nil)
    possible_refs = ['v' + myref, myref]
    possible_refs += possible_refs.map { |ref| "#{cookbook_name}-#{ref}" } if cookbook_name
    possible_refs += possible_refs.map { |ref| ref.chomp('.0') } if myref[/\.0$/]
    existing_ref = possible_refs.find do |ref|
      begin
        repo.checkout(ref)
      rescue ::Git::Error
        false
      end
    end
    raise "Impossible to find existing references to #{possible_refs} in #{repo.remote.url}" unless existing_ref
    existing_ref
  end

  # Sort tags by version and filter out invalid version tags
  #
  # @param tags [Array<Git::Object::Tag>] git tags
  # @return [Array] git tags sorted by version
  def sort_by_version(tags)
    tags.sort_by do |t|
      begin
        Gem::Version.new(t.name.gsub(/^v/, ''))
      rescue ArgumentError => e
        # Skip tag if version is not valid (i.e. a String)
        raise unless e.message && e.message.include?('Malformed version number string')
        Gem::Version.new('0.0.0')
      end
    end
  end

  # Formats commit changelog to be more readable
  #
  # @param name [String] cookbook name
  # @param data [Hash] cookbook versions and source url data
  # @return [String] formatted changelog
  def format_output(name, data)
    output = ["\nChangelog for #{name}: #{data['current_version']}->#{data['target_version']}"]
    output << '=' * output.first.size
    output << if data['current_version']
                git_changelog(data['source_url'], data['current_version'], data['target_version'], name)
              else
                'Cookbook was not in the Policyfile.lock.json'
              end

    output.join("\n")
  end

  # Filters out cookbooks which are not updated, are not used after update
  #
  # @param [Hash] cookbook versions and source url data
  # @return [true, false]
  def reject_version_filter(data)
    raise 'Data containing versions is nil' if data.nil?
    data['current_version'] == data['target_version'] || data['target_version'].nil?
  end

  # Search for cookbook downgrade and raise an error if any
  def validate_downgrade!(data)
    downgrade = data.select do |_, ck|
      # Do not try to validate downgrade on non-sementic versions (e.g. git revision)
      ck['target_version'] =~ VERSION_REGEX && ck['current_version'] =~ VERSION_REGEX &&
        ::Gem::Version.new(ck['target_version']) < ::Gem::Version.new(ck['current_version'])
    end

    return if downgrade.empty?

    details = downgrade.map { |name, data| "#{name} (#{data['current_version']} -> #{data['target_version']})" }
    raise "Trying to downgrade following cookbooks: #{details.join(', ')}"
  end

  # Generates Policyfile changelog
  #
  # @return [String] formatted version changelog
  def generate_changelog(prevent_downgrade: false)
    lock_current = read_policyfile_lock(@policyfile_dir)
    current = versions(lock_current['cookbook_locks'], 'current')

    lock_target = update_policyfile_lock
    target = versions(lock_target['cookbook_locks'], 'target')

    updated_cookbooks = current.deep_merge(target).reject { |_name, data| reject_version_filter(data) }
    changelog_cookbooks = if @with_dependencies || @cookbooks_to_update.nil?
                            updated_cookbooks
                          else
                            updated_cookbooks.select { |name, _data| @cookbooks_to_update.include?(name) }
                          end

    validate_downgrade!(updated_cookbooks) if prevent_downgrade

    generate_changelog_from_versions(changelog_cookbooks)
  end

  # Generates Policyfile changelog
  #
  # @param cookbook_versions. Format is { 'NAME'  => { 'current_version' => 'VERSION', 'target_version' => 'VERSION' }
  # @return [String] formatted version changelog
  def generate_changelog_from_versions(cookbook_versions)
    lock_current = read_policyfile_lock(@policyfile_dir)
    sources = cookbook_versions.map do |name, data|
      [name, get_source_url(lock_current['cookbook_locks'][name]['source_options'])] if data['current_version']
    end.compact.to_h
    cookbook_versions.deep_merge(sources).map { |name, data| format_output(name, data) }.join("\n")
  end
end
