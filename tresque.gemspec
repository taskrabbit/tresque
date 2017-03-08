# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'tresque/version'

Gem::Specification.new do |spec|
  spec.name          = "tresque"
  spec.version       = TResque::VERSION
  spec.authors       = ["Brian Leonard"]
  spec.email         = ["brian@bleonard.com"]
  spec.description   = %q{Background me}
  spec.summary       = %q{Background me}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  # spec.add_development_dependency "bundler", "~> 1.3"
  # spec.add_development_dependency "rake"


  spec.add_dependency('resque', ['>= 1.10.0', '< 2.0'])
  spec.add_dependency('activesupport', '4.1.8')
  spec.add_dependency('resque-scheduler')
  spec.add_dependency('resque-retry')
  spec.add_dependency('resque-bus')
end
