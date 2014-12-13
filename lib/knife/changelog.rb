require "knife/changelog/version"
require "berkshelf"
require 'chef/knife'
require 'mixlib/shellout'

class Chef
  class Knife
    class Changelog < Knife

      def initialize
        @tmp_prefix = 'knife-changelog'
      end

      def ck_location(name, options = {})
        berksfile = Berkshelf::Berksfile.from_options(options)
        berksfile.lockfile.find(name).location
      end

      def execute(name,options= {})
        loc =ck_location(name, options)
        case loc
        when NilClass
          raise "Cannt handle default location yet"
        when Berkshelf::GitLocation
          handle_git loc
        else
          raise "Cannot handle #{loc.class} yet"
        end
      end

      def handle_git(location)
        tmp_dir = shallow_clone(@tmp_prefix,location.uri)

        rev_parse = location.instance_variable_get(:@rev_parse)
        ls_tree = Mixlib::ShellOut.new("git ls-tree -r #{rev_parse}", :cwd => tmp_dir)
        ls_tree.run_command
        changelog = ls_tree.stdout.lines.find { |line| line =~ /\s(changelog.*$)/i }
        if changelog
          puts "found changelog file : " + $1
          diff = Mixlib::ShellOut.new("git diff #{location.revision.rstrip}..#{rev_parse} -- #{$1}", :cwd => tmp_dir)
          puts diff.command
          diff.run_command
          puts "--- Changelog ---"
          puts diff.stdout.lines.collect {|line| $1 if line =~ /^\+([^+].*)/}.compact
          puts "-----------------"
        else
          generate_git_history(tmp_dir, location)
        end
        
      end

      def generate_git_history(tmp_dir, location)
        raise "changelog from git is not yet handled !"
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
