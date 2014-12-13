require "knife/changelog/version"
require "berkshelf"
require 'chef/knife'
require 'mixlib/shellout'

class Chef
  class Knife
    class Changelog < Knife

      def initialize(options = {})
        @tmp_prefix = 'knife-changelog'
        @berksfile = Berkshelf::Berksfile.from_options(options)
      end

      def ck_dep(name)
        @berksfile.lockfile.find(name)
      end

      def ck_location(name)
       ck_dep(name).location
      end

      def version_for(name)
        # FIXME uses public methods instead
        @berksfile.lockfile.graph.instance_variable_get(:@graph)[name].version
      end

      def execute(name)
        loc = ck_location(name)
        changelog = case loc
                    when NilClass
                      handle_source name, ck_dep(name)
                    when Berkshelf::GitLocation
                      handle_git loc
                    else
                      raise "Cannot handle #{loc.class} yet"
                    end
        print_changelog(changelog)
      end

      def print_changelog(changelog)
        puts "--- Changelog ---"
        puts changelog
        puts "-----------------"
      end

      def handle_source(name, dep)
        ck = noauth_rest.get_rest("https://supermarket.getchef.com/api/v1/cookbooks/#{name}")
        url = ck['source_url'] || ck ['external_url']
        case url
        when nil
          fail "No external url for #{name}, can't find any changelog source"
        when /github.com\/(.*)(.git)?/
          options = {
            :github => $1,
            :revision => 'v' + version_for(name), 
          }
          location = Berkshelf::GithubLocation.new dep, options
          handle_git(location)
        else
          fail "External url #{url} points to unusable location!"
        end
      end

      def handle_git(location)
        tmp_dir = shallow_clone(@tmp_prefix,location.uri)

        rev_parse = location.instance_variable_get(:@rev_parse)
        cur_rev = location.revision.rstrip
        ls_tree = Mixlib::ShellOut.new("git ls-tree -r #{rev_parse}", :cwd => tmp_dir)
        ls_tree.run_command
        changelog = ls_tree.stdout.lines.find { |line| line =~ /\s(changelog.*$)/i }
        if changelog
          puts "Found changelog file : " + $1
          generate_from_changelog_file($1, cur_rev, rev_parse, tmp_dir)
        else
          generate_from_git_history(tmp_dir, location, cur_rev, rev_parse)
        end
      end

      def generate_from_changelog_file(filename, current_rev, rev_parse, tmp_dir)
        diff = Mixlib::ShellOut.new("git diff #{current_rev}..#{rev_parse} -- #{filename}", :cwd => tmp_dir)
        diff.run_command
        diff.stdout.lines.collect {|line| $1 if line =~ /^\+([^+].*)/}.compact
      end

      def generate_from_git_history(tmp_dir, location, current_rev, rev_parse)
        log = Mixlib::ShellOut.new("git log --abbrev-commit --pretty=oneline #{current_rev}..#{rev_parse}", :cwd => tmp_dir)
        log.run_command
        log.stdout
      end

      def shallow_clone(tmp_prefix, uri)
        dir = Dir.mktmpdir(tmp_prefix)
        clone = Mixlib::ShellOut.new("git clone --bare #{uri} bare-clone", :cwd => dir)
        clone.run_command
        ::File.join(dir, 'bare-clone')
      end

    end
  end
end
