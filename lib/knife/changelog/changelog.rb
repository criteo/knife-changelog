# coding: utf-8
require 'chef/log'
require 'chef/knife'
require 'chef/version_class'
require 'rest-client'
require 'json'
require_relative 'git'

class KnifeChangelog
  class Changelog

    Location = Struct.new(:uri, :revision, :rev_parse) do
      # todo move this method to Changelog::Berkshelf
      def self.from_berk_git_location(location)
        Location.new(location.uri,
                     location.revision.strip,
                     location.instance_variable_get(:@rev_parse))
      end
    end

    def initialize(config)
      @tmp_prefix = 'knife-changelog'
      @config   = config
      @tmp_dirs = []
    end

    # returns a list of all cookbooks names
    def all_cookbooks
      raise NotImplementedError
    end

    # return true if cookbook is not already listed as dependency
    def new_cookbook?(name)
      raise NotImplementedError
    end

    # return true if cookbook is downloaded from supermarket
    def supermarket?(name)
      raise NotImplementedError
    end

    # return true if cookbook is downloaded from git
    def git?(name)
      raise NotImplementedError
    end

    # return true if cookbook is downloaded from local path
    def local?(name)
      raise NotImplementedError
    end

    # return a Changelog::Location for a given cookbook
    def git_location(name)
      raise NotImplementedError
    end

    # return a list of supermarket uri for a given cookbook
    # example: [ 'https://supermarket.chef.io' ]
    def supermarkets_for(name)
      raise NotImplementedError
    end

    # return current locked version for a given cookbook
    def guess_version_for(name)
      raise NotImplementedError
    end



    def run(cookbooks)
      changelog = []
      begin
        if cookbooks.empty? and @config[:allow_update_all]
          cks = all_cookbooks
        else
          cks = cookbooks
        end
        changelog += cks.map do |cookbook|
          Chef::Log.debug "Checking changelog for #{cookbook} (cookbook)"
          execute cookbook
        end
        subs = @config[:submodules] || []
        subs = subs.split(',') if subs.is_a? String
        changelog += subs.map do |submodule|
          Chef::Log.debug "Checking changelog for #{submodule} (submodule)"
          execute(submodule, true)
        end
      ensure
        clean
      end
      changelog.compact.join("\n")
    end

    def clean
      @tmp_dirs.each do |dir|
        FileUtils.rm_rf dir
      end
    end

    def handle_new_cookbook
      stars = '**' if @config[:markdown]
      ["#{stars}Cookbook was not in the berksfile#{stars}"]
    end

    def execute(name, submodule = false)
      version_change, changelog = if submodule
                                    handle_submodule(name)
                                  elsif new_cookbook?(name)
                                    ['', handle_new_cookbook]
                                  else
                                    case true
                                    when supermarket?(name)
                                      handle_source(name)
                                    when git?(name)
                                      handle_git(name, git_location(name))
                                    when local?(name)
                                      Chef::Log.debug "path location are always at the last version"
                                      ['', '']
                                    else
                                      raise "Cannot handle #{loc.class} yet"
                                    end
                                  end
      format_changelog(name, version_change, changelog)
    end

    def format_changelog(name, version_change, changelog)
      if changelog.empty?
        nil
      else
        full = ["Changelog for #{name}: #{version_change}"]
        full << '=' * full.first.size
        full << changelog
        full << ''
        full.compact.join("\n")
      end
    end

    def get_from_supermarket_sources(name)
      supermarkets_for(name).map do |uri|
        begin
          # TODO: we could call /universe endpoint once
          # instead of calling /api/v1/cookbooks/ for each cookbook
          RestClient::Request.execute(
            url: "#{uri}/api/v1/cookbooks/#{name}",
            method: :get,
            verify_ssl: false # TODO make this configurable
          )
        rescue => e
          Chef::Log.debug "Error fetching package from supermarket #{e.class.name} #{e.message}"
          nil
        end
      end
        .compact
        .map { |json| JSON.parse(json) }
        .sort_by { |ck| cookbook_highest_version(ck) }
        .map { |ck| ck['source_url'] || ck ['external_url'] }
        .last
        .tap do |source|
          raise "Cannot find any changelog source for #{name}" unless source
        end
    end

    def cookbook_highest_version(json)
      json['versions']
        .map { |version_url| Chef::Version.new(version_url.gsub(/.*\//, '')) }
        .sort
        .last
    end

    def handle_source(name)
      url = get_from_supermarket_sources(name)
      raise "No source found in supermarket for cookbook '#{name}'" unless url
      Chef::Log.debug("Using #{url} as source url")
      case url.strip
      when /(gitlab.*|github).com\/([^.]+)(.git)?/
        url = "https://#{$1}.com/#{$2.chomp('/')}.git"
        location = Location.new(url, guess_version_for(name), 'master')
        handle_git(name, location)
      else
        fail "External url #{url} points to unusable location! (cookbook: #{name})"
      end
    end

    def detect_cur_revision(name, rev, git)
      unless git.revision_exists?(rev)
        prefixed_rev = 'v' + rev
        return prefixed_rev if git.revision_exists?(prefixed_rev)
        fail "#{rev} is not an existing revision (#{name}), not a tag/commit/branch name."
      end
      rev
    end

    def handle_submodule(name)
      subm_url = Mixlib::ShellOut.new("git config --list| grep ^submodule | grep ^submodule.#{name}.url")
      subm_url.run_command
      subm_url.error!
      url = subm_url.stdout.lines.first.split('=')[1].chomp
      subm_revision = Mixlib::ShellOut.new("git submodule status #{name}")
      subm_revision.run_command
      subm_revision.error!
      revision = subm_revision.stdout.strip.split(' ').first
      revision.gsub!(/^\+/, '')
      loc = Location.new(url, revision, 'master')
      handle_git(name, loc)
    end

    # take cookbook name and Changelog::Location instance
    def handle_git(name, location)
      # todo: remove this compat check
      raise "should be a location" unless location.is_a?(Changelog::Location)
      git = Git.new(@tmp_prefix, location.uri)
      @tmp_dirs << git.shallow_clone

      rev_parse = location.rev_parse
      cur_rev = detect_cur_revision(name, location.revision, git)
      changelog_file = git.files(rev_parse).find { |line| line =~ /\s(changelog.*$)/i }
      changelog = if changelog_file and !@config[:ignore_changelog_file]
                    Chef::Log.info "Found changelog file : " + $1
                    generate_from_changelog_file($1, cur_rev, rev_parse, git)
                  end
      changelog ||= generate_from_git_history(git, location, cur_rev, rev_parse)
      ["#{cur_rev}->#{rev_parse}", changelog]
    end

    def generate_from_changelog_file(filename, current_rev, rev_parse, git)
      ch = git.diff(filename, current_rev, rev_parse)
              .collect { |line| $1.strip if line =~ /^{\+(.*)\+}$/ }.compact
              .map { |line| line.gsub(/^#+(.*)$/, "\\1\n---")} # replace section by smaller header
              .select { |line| !(line =~ /^===+/)}.compact # remove header lines
      ch.empty? ? nil : ch
    end

    def generate_from_git_history(git, location, current_rev, rev_parse)
      c = git.log(current_rev, rev_parse)
      n = https_url(location)
      c = linkify(n, c) if @config[:linkify] and n
      c = c.map { |line| "* " + line } if @config[:markdown]
      c = c.map { |line| line.strip } # clean end of line
      c
    end

    def linkify(url, changelog)
      changelog.map do |line|
        line.gsub(/^([a-f0-9]+) (.*)$/, '\2 (%s/commit/\1) ' % [url.chomp('.git')])
      end
    end

    def https_url(location)
      if location.uri =~ /^\w+:\/\/(.*@)?(.*)(\.git)?/
        "https://%s" % [ $2 ]
      else
        fail "Cannot guess http url from git remote url: #{location.uri}"
      end
    end

    def short(location)
      if location.uri =~ /([\w-]+)\/([\w-]+)(\.git)?$/
        "%s/%s" % [$1,$2]
      end
    end
  end
end
