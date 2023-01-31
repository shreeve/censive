# encoding: utf-8

Gem::Specification.new do |s|
  s.name        = "censive"
  s.version     = "0.1"
  s.author      = "Steve Shreeve"
  s.email       = "steve.shreeve@gmail.com"
  s.description = "A quick and lightweight CVS handling library for Ruby"
  s.summary     = "A quick and lightweight CVS handling library for Ruby"
  s.homepage    = "https://github.com/shreeve/censive"
  s.license     = "MIT"
  s.files       = `git ls-files`.split("\n") - %w[.gitignore]
  s.executables = `cd bin && git ls-files .`.split("\n")
end
