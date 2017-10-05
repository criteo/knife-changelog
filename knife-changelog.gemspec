# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'knife/changelog/version'

Gem::Specification.new do |spec|
  spec.name          = "knife-changelog"
  spec.version       = Knife::Changelog::VERSION
  spec.authors       = ["Gregoire Seux"]
  spec.email         = ["kamaradclimber@gmail.com"]
  spec.summary       = %q{Facilitate access to cookbooks changelog}
  spec.description   = %q{}
  spec.homepage      = "https://github.com/kamaradclimber/knife-changelog"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "pry"


  spec.add_dependency  'berkshelf'
  spec.add_dependency  'rest-client'
  spec.add_dependency  'mixlib-shellout'
  spec.add_dependency  'chef'
  spec.add_dependency  'chef-dk'
end
