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
        @changelog = KnifeChangelog::Changelog.new(berksfile, config)
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

      option :submodules,
        :long => '--submodules SUBMODULE[,SUBMODULE]',
        :description => 'Submoduless to check for changes as well (comma separated)'


      def run
        Log.info config
        @changelog.run(@name_args)
      end
    end

  end
end
