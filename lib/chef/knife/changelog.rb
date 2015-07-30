require "knife/changelog/version"
require "knife/changelog/changelog"
require "berkshelf"
require 'chef/knife'
require 'mixlib/shellout'

class Chef
  class Knife
    class Changelog < Knife

      banner 'knife changelog COOKBOOK [COOKBOOK ...]'

      def initialize(options)
        super
        berksfile = Berkshelf::Berksfile.from_options({})
        @changelog = KnifeChangelog::Changelog.new(berksfile.lockfile.locks, config, berksfile.sources)
      end

      option :linkify,
        :short => '-l',
        :long  => '--linkify',
        :description => 'add markdown links where relevant',
        :boolean => true

      option :markdown,
        :short => '-m',
        :long  => '--markdown',
        :description => 'use markdown syntax',
        :boolean => true

      option :ignore_changelog_file,
        :long => '--ignore-changelog-file',
        :description => "Ignore changelog file presence, use git history instead",
        :boolean => true

      option :allow_update_all,
        :long => '--allow-update-all',
        :description => "If no cookbook given, check all Berksfile",
        :boolean => true,
        :default => true

      option :submodules,
        :long => '--submodules SUBMODULE[,SUBMODULE]',
        :description => 'Submoduless to check for changes as well (comma separated)'


      def run
        Log.info config
        changelog = @changelog.run(@name_args)
        puts changelog
      end
    end

  end
end
