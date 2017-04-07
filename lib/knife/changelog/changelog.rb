require 'chef/log'
require 'chef/knife'
require 'rest-client'
require 'json'
require 'berkshelf'

class KnifeChangelog
  class Changelog
    def initialize(locked_versions, config = {}, sources=[])
      @tmp_prefix = 'knife-changelog'
      @locked_versions = locked_versions
      @config   = config
      @tmp_dirs = []
      @sources = sources
      if sources.empty? # preserve api compat
        @sources = [ Berkshelf::Source.new("https://supermarket.chef.io") ]
      end
    end

    def run(cookbooks)
      changelog = []
      begin
        if cookbooks.empty? and @config[:allow_update_all]
          cks = @locked_versions.keys
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
        FileUtils.rm_r dir
      end
    end

    def ck_dep(name)
      @locked_versions[name]
    end

    def ck_location(name)
      begin
        ck_dep(name).location
      rescue
        puts "Failed to get location for cookbook: #{name}"
        raise
      end
    end

    def guess_version_for(name)
      @locked_versions[name].locked_version.to_s
    end

    def handle_new_cookbook(name)
      stars = '**' if @config[:markdown]
      ["#{stars}Cookbook was not in the berksfile#{stars}"]
    end

    def execute(name, submodule=false)
      changelog = if submodule
                    handle_submodule(name)
                  elsif ck_dep(name).nil?
                    handle_new_cookbook(name)
                  else
                    loc = ck_location(name)
                    case loc
                    when NilClass
                      handle_source name, ck_dep(name)
                    when Berkshelf::GitLocation
                      handle_git name, loc
                    when Berkshelf::PathLocation
                      Chef::Log.debug "path location are always at the last version"
                      ""
                    else
                      raise "Cannot handle #{loc.class} yet"
                    end
                  end
      format_changelog(name, changelog)
    end

    def format_changelog(name, changelog)
      if changelog.empty?
        nil
      else
        [
          "Changelog for #{name}",
          "==============#{'=' * name.size}",
          changelog,
          ''
        ].compact.join("\n")
      end
    end

    def get_from_supermarket_sources(name)
      @sources.map do |s|
        begin
          RestClient::Request.execute(
            url: "#{s.uri}/api/v1/cookbooks/#{name}",
            method: :get,
            verify_ssl: false # TODO make this configurable
          )
        rescue
          nil
        end
      end
        .compact
        .map { |json| JSON.parse(json) }
        .sort_by { |ck| Gem::Version.new(ck['latest_version'].split('/').last) }
        .map { |ck| ck['source_url'] || ck ['external_url'] }
        .last
        .tap do |source|
          raise "Canot find any changelog source for #{name}" unless source
        end
    end

    def handle_source(name, dep)
      url = get_from_supermarket_sources(name)
      raise "No source found in supermarket for cookbook '#{name}'" unless url
      Chef::Log.debug("Using #{url} as source url")
      case url.strip
      when /(gitlab.*|github).com\/(.*)(.git)?/
        url = "https://#{$1}.com/#{$2.chomp('/')}.git"
        options = {
          :git => url,
          :revision => guess_version_for(name),
        }
        location = Berkshelf::GitLocation.new dep, options
        handle_git(name, location)
      else
        fail "External url #{url} points to unusable location! (cookbook: #{name})"
      end
    end

    def revision_exists?(dir, revision)
      Chef::Log.debug "Testing existence of #{revision}"
      revlist = Mixlib::ShellOut.new("git rev-list --quiet #{revision}", :cwd => dir)
      revlist.run_command
      not revlist.error?
    end

    def detect_cur_revision(name, dir, rev)
      unless revision_exists?(dir, rev)
        prefixed_rev = 'v' + rev
        return prefixed_rev if revision_exists?(dir, prefixed_rev)
        fail "#{rev} is not a valid revision (#{name})"
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
      loc = Berkshelf::Location.init(nil, {git: url,revision: revision})
      handle_git(name, loc)
    end

    def handle_git(name, location)
      tmp_dir = shallow_clone(@tmp_prefix,location.uri)

      rev_parse = location.instance_variable_get(:@rev_parse)
      cur_rev = location.revision.rstrip
      cur_rev = detect_cur_revision(name, tmp_dir, cur_rev)
      ls_tree = Mixlib::ShellOut.new("git ls-tree -r #{rev_parse}", :cwd => tmp_dir)
      ls_tree.run_command
      changelog_file = ls_tree.stdout.lines.find { |line| line =~ /\s(changelog.*$)/i }
      changelog = if changelog_file and !@config[:ignore_changelog_file]
                    Chef::Log.info "Found changelog file : " + $1
                    generate_from_changelog_file($1, cur_rev, rev_parse, tmp_dir)
                  end
      changelog || generate_from_git_history(tmp_dir, location, cur_rev, rev_parse)
    end

    def generate_from_changelog_file(filename, current_rev, rev_parse, tmp_dir)
      diff = Mixlib::ShellOut.new("git diff #{current_rev}..#{rev_parse} --word-diff -- #{filename}", :cwd => tmp_dir)
      diff.run_command
      ch = diff.
        stdout.
        lines.
        collect {|line| $1.strip if line =~ /^{\+(.*)\+}$/}.compact.
        map { |line| line.gsub(/^#+(.*)$/, "\\1\n---")}. # replace section by smaller header
        select { |line| !(line =~ /^===+/)}.compact # remove header lines
      ch.empty? ? nil : ch
    end

    def generate_from_git_history(tmp_dir, location, current_rev, rev_parse)
      log = Mixlib::ShellOut.new("git log --no-merges --abbrev-commit --pretty=oneline #{current_rev}..#{rev_parse}", :cwd => tmp_dir)
      log.run_command
      c = log.stdout.lines
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

    def shallow_clone(tmp_prefix, uri)
      dir = Dir.mktmpdir(tmp_prefix)
      @tmp_dirs << dir
      clone = Mixlib::ShellOut.new("git clone --bare #{uri} bare-clone", :cwd => dir)
      clone.run_command
      clone.error!
      ::File.join(dir, 'bare-clone')
    end

  end
end
