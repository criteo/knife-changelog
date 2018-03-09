# frozen_string_literal: true

require 'chef'
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
    updater = ChefDK::Command::Update.new
    updater.run([@policyfile_path, @cookbooks_to_update].flatten)
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
    raise 'Cookbook locks empty or nil' if locks.nil? or locks.empty?
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
      c_tag, t_tag = correct_tags("v#{current}", "v#{target}", repo)
      repo.log.between(c_tag, t_tag)
    else
      c_tag, t_tag = correct_tags(current, target, repo)
      repo.log.between(c_tag, t_tag)
    end.map do |commit|
      "#{commit.sha[0, 7]} #{commit.message.lines.first.strip}"
    end.join("\n")
  end

  # Used to make #git_changelog method more readable
  #
  # @param current [String] current cookbook version tag
  # @param target [String] target cookbook version tag
  # @param repo [Git::Base] Git repository object
  # @return [true, false]
  def correct_tags(current, target, repo)
    [git_tag(current, repo), git_tag(target, repo)]
  end

  # Tries to convert a supermarket tag to a git tag
  # if there is a difference in formatting between the two.
  # This is issue is present for the 'java' cookbook.
  # https://github.com/agileorbit-cookbooks/java/issues/450
  #
  # @param tag [String] version tag
  # @param repo [Git::Base] Git repository object
  # @return [String]
  def git_tag(tag, repo)
    return tag if repo.checkout(tag)
  rescue ::Git::GitExecuteError
    begin
      rescue_tag = tag.chomp('.0') if tag[/\.0$/]
      return rescue_tag if repo.checkout(rescue_tag)
    rescue ::Git::GitExecuteError
      raise 'Difference between Git and Supermarket tags'
    end
  end

  # Detects the format of a Git tag - v1.0.0 or 1.0.0
  #
  # @param repo [Git::Base] Git repository object
  # @return [String] Git tag versioning type
  def tag_format(repo)
    sort_by_version(repo.tags).last.name[/^v/] ? 'v' : ''
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
        Gem::Version.new(nil) if e.to_s.include?('Malformed version number string')
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
                git_changelog(data['source_url'], data['current_version'], data['target_version'])
              else
                'Cookbook was not in the Policyfile.lock.json'
              end

    output.join("\n")
  end

  # Filters out cookbooks which are not updated, are not used after update or
  # are newly added as dependencies during update
  #
  # @param [Hash] cookbook versions and source url data
  # @return [true, false]
  def reject_version_filter(data)
    raise 'Data containing versions is nil' if data.nil?
    data['current_version'] == data['target_version'] || data['target_version'].nil?
  end

  # Generates Policyfile changelog
  #
  # @return [String] formatted version changelog
  def generate_changelog
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
    sources = {}
    changelog_cookbooks.each_key do |name|
      sources[name] = get_source_url(lock_target['cookbook_locks'][name]['source_options'])
    end
    changelog_cookbooks.deep_merge(sources).map { |name, data| format_output(name, data) }.join("\n")
  end
end
