# -*- encoding: utf-8 -*-

$:.push File.expand_path("../lib", __FILE__)
require "trinity/version"

Gem::Specification.new do |s|
  s.name = "trinity"
  s.version = Trinity::VERSION
  s.authors = ["Denis Boldinov"]
  s.email = ["positivejob@yandex.ru"]
  s.homepage = ""
  s.summary = %q{Trinity automation helper}
  s.description = s.summary

  s.add_dependency('chronic')
  s.add_dependency('activeresource')
  s.add_dependency('mail')
  s.add_dependency('thor')
  s.add_dependency('xmpp4r')

  s.rubyforge_project = "trinity"

  s.files += Dir.glob("bin/**/*")
  s.files += Dir.glob("lib/**/*.rb")

  s.executables = %w(trinity)

  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  #s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
end
