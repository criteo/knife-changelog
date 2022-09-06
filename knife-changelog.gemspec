# frozen_string_literal: true

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = 'knife-changelog'
  spec.version       = '1.7.0'
  spec.authors       = ['Gregoire Seux']
  spec.email         = ['kamaradclimber@gmail.com']
  spec.summary       = 'Facilitate access to cookbooks changelog'
  spec.description   = ''
  spec.homepage      = 'https://github.com/kamaradclimber/knife-changelog'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'webmock'

  spec.add_dependency  'berkshelf'
  spec.add_dependency  'chef'
  spec.add_dependency  'chef-cli'
  spec.add_dependency  'deep_merge'
  spec.add_dependency  'git'
  spec.add_dependency  'mixlib-shellout'
  spec.add_dependency  'rest-client'
end
