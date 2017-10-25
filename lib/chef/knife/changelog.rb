require 'chef/knife'
require 'mixlib/shellout'

class Chef
  class Knife
    class Changelog < Knife

      banner 'knife changelog COOKBOOK [COOKBOOK ...]'

      deps do
        require "knife/changelog/version"
        require "knife/changelog/changelog"
        require "knife/changelog/policyfile"
        require "knife/changelog/berksfile"
        require "berkshelf"
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

      option :policyfile,
        :long => '--policyfile PATH',
        :description => 'Link to policyfile, defaults to Policyfile.rb',
        :default => 'Policyfile.rb'

      option :update,
        :long => '--update',
        :description => 'Update Berksfile'

      def run
        Log.info config
        @changelog = if config[:policyfile] && File.exists?(config[:policyfile])
                       KnifeChangelog::Changelog::Policyfile.new(config[:policyfile], config)
                     else
                       berksfile = Berkshelf::Berksfile.from_options({})
                       KnifeChangelog::Changelog::Berksfile.new(berksfile, config)
                     end
        changelog_text = @changelog.run(@name_args)
        puts changelog_text
      end
    end

  end
end
